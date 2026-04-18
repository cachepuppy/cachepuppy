import { createEnvelope, isEnvelope } from "./protocol.js";
import { MockTransport } from "./transport/mockTransport.js";
import { PhoenixTransport } from "./transport/phoenixTransport.js";
import type { CacheSetDataOptions, Transport, TopicStateResponse } from "./transport/transport.js";
import type {
  CachePuppyEnvelope,
  ClientEventMap,
  ClientOptions,
  ConnectionState,
  ReconnectConfig,
  TopicHandler,
  TopicWebhookConfigOptions,
} from "./types.js";

class TypedEventBus {
  private handlers = new Map<keyof ClientEventMap, Set<(payload: unknown) => void>>();

  on<K extends keyof ClientEventMap>(event: K, handler: (payload: ClientEventMap[K]) => void): () => void {
    if (!this.handlers.has(event)) {
      this.handlers.set(event, new Set());
    }
    const set = this.handlers.get(event)!;
    set.add(handler as (payload: unknown) => void);
    return () => set.delete(handler as (payload: unknown) => void);
  }

  emit<K extends keyof ClientEventMap>(event: K, payload: ClientEventMap[K]): void {
    const set = this.handlers.get(event);
    if (!set) {
      return;
    }
    for (const handler of set.values()) {
      handler(payload);
    }
  }
}

const DEFAULT_RECONNECT: ReconnectConfig = {
  enabled: true,
  initialDelayMs: 500,
  maxDelayMs: 10_000,
  factor: 2,
};

export class CachePuppyClient {
  private state: ConnectionState = "idle";
  private readonly events = new TypedEventBus();
  private readonly transport: Transport;
  private readonly reconnect: ReconnectConfig;
  private readonly clientId: string;
  private readonly topicHandlers = new Map<string, Set<TopicHandler>>();
  private unlistenEnvelope?: () => void;

  constructor(private readonly options: ClientOptions) {
    this.transport =
      options.transport === "mock"
        ? new MockTransport()
        : new PhoenixTransport(options.url, options.authToken, options.clientId);
    this.reconnect = { ...DEFAULT_RECONNECT, ...(options.reconnect ?? {}) };
    this.clientId = options.clientId ?? `client_${Date.now()}_${Math.floor(Math.random() * 10000)}`;
  }

  private setState(state: ConnectionState): void {
    this.state = state;
    this.events.emit("stateChange", { state });
  }

  getState(): ConnectionState {
    return this.state;
  }

  on = this.events.on.bind(this.events);

  async connect(): Promise<void> {
    if (this.state === "connected" || this.state === "connecting") {
      return;
    }

    this.setState("connecting");
    await this.transport.connect(this.clientId);
    this.unlistenEnvelope = this.transport.onEnvelope(this.clientId, (msg) => this.handleEnvelope(msg));
    this.setState("connected");
    this.events.emit("connected", undefined);

    for (const topic of this.topicHandlers.keys()) {
      await this.transport.sendEnvelope(this.clientId, createEnvelope({ type: "subscribe", topic }));
    }
  }

  async disconnect(reason?: string): Promise<void> {
    if (this.state === "destroyed") {
      return;
    }
    await this.transport.disconnect(this.clientId);
    this.unlistenEnvelope?.();
    this.setState("disconnected");
    this.events.emit("disconnected", { reason });
  }

  async destroy(): Promise<void> {
    await this.disconnect("destroy");
    this.setState("destroyed");
  }

  private handleEnvelope(message: CachePuppyEnvelope): void {
    if (!isEnvelope(message)) {
      this.events.emit("error", new Error("ProtocolError: invalid envelope"));
      return;
    }
    this.events.emit("message", message);

    if (message.type === "system" && message.event === "presence_change" && message.topic) {
      const rawPayload =
        message.payload && typeof message.payload === "object" && !Array.isArray(message.payload)
          ? (message.payload as Record<string, unknown>)
          : {};
      const n = rawPayload.clientCount;
      const clientCount = typeof n === "number" && Number.isFinite(n) ? Math.floor(n) : 0;
      this.events.emit("topicPresence", { topic: message.topic, clientCount });
    }

    if (message.type === "publish" && message.topic) {
      const handlers = this.topicHandlers.get(message.topic);
      if (handlers) {
        for (const handler of handlers.values()) {
          handler(message);
        }
      }
    }
  }

  async subscribe(topic: string, handler: TopicHandler): Promise<() => void> {
    const isNewTopic = !this.topicHandlers.has(topic);
    if (isNewTopic) {
      this.topicHandlers.set(topic, new Set());
    }
    this.topicHandlers.get(topic)!.add(handler);
    if (isNewTopic && this.state === "connected") {
      await this.transport.sendEnvelope(this.clientId, createEnvelope({ type: "subscribe", topic }));
    }
    return () => {
      const set = this.topicHandlers.get(topic);
      if (!set) {
        return;
      }
      set.delete(handler);
      if (set.size === 0) {
        this.topicHandlers.delete(topic);
        void this.transport.sendEnvelope(this.clientId, createEnvelope({ type: "unsubscribe", topic }));
      }
    };
  }

  async unsubscribe(topic: string): Promise<void> {
    this.topicHandlers.delete(topic);
    await this.transport.sendEnvelope(this.clientId, createEnvelope({ type: "unsubscribe", topic }));
  }

  async publish(topic: string, event: string, payload: unknown): Promise<void> {
    await this.transport.sendEnvelope(this.clientId, createEnvelope({ type: "publish", topic, event, payload }));
  }

  async setTopicState(topic: string, payload: Record<string, unknown>): Promise<Record<string, unknown>> {
    if (!this.transport.setState) {
      throw new Error("TransportError: setState is not supported by this transport");
    }

    return this.transport.setState(this.clientId, topic, payload);
  }

  async configureTopicWebhook(topic: string, options: TopicWebhookConfigOptions): Promise<void> {
    if (!this.transport.configureTopicWebhook) {
      throw new Error("TransportError: configureTopicWebhook is not supported by this transport");
    }

    await this.transport.configureTopicWebhook(this.clientId, topic, options);
  }

  async getTopicState(topic: string): Promise<Record<string, unknown>> {
    if (!this.transport.getState) {
      throw new Error("TransportError: getState is not supported by this transport");
    }

    return this.transport.getState(this.clientId, topic);
  }

  async getTopicStateWithMeta(topic: string): Promise<TopicStateResponse> {
    if (this.transport.getStateWithMeta) {
      return this.transport.getStateWithMeta(this.clientId, topic);
    }

    const state = await this.getTopicState(topic);
    return { state };
  }

  async setData(table: string, key: string, value: unknown, options?: CacheSetDataOptions): Promise<unknown> {
    if (!this.transport.setData) {
      throw new Error("TransportError: setData is not supported by this transport");
    }

    return this.transport.setData(this.clientId, table, key, value, options);
  }

  async getData(table: string, key: string): Promise<unknown> {
    if (!this.transport.getData) {
      throw new Error("TransportError: getData is not supported by this transport");
    }

    return this.transport.getData(this.clientId, table, key);
  }

  async deleteData(table: string, key: string): Promise<boolean> {
    if (!this.transport.deleteData) {
      throw new Error("TransportError: deleteData is not supported by this transport");
    }

    return this.transport.deleteData(this.clientId, table, key);
  }

  async setSessionState(payload: Record<string, unknown>): Promise<Record<string, unknown>> {
    if (!this.transport.setSessionState) {
      throw new Error("TransportError: setSessionState is not supported by this transport");
    }

    return this.transport.setSessionState(this.clientId, payload);
  }

  async getSessionState(): Promise<Record<string, unknown>> {
    if (!this.transport.getSessionState) {
      throw new Error("TransportError: getSessionState is not supported by this transport");
    }

    return this.transport.getSessionState(this.clientId);
  }

  getChannelJoinMeta(topic: string): Record<string, unknown> | undefined {
    return this.transport.getChannelJoinMeta?.(this.clientId, topic);
  }

  async clearTopicState(topic: string): Promise<boolean> {
    if (!this.transport.clearTopicState) {
      throw new Error("TransportError: clearTopicState is not supported by this transport");
    }

    return this.transport.clearTopicState(this.clientId, topic);
  }

  async onStateUpdated(topic: string, handler: (state: Record<string, unknown>) => void): Promise<() => void> {
    return this.subscribe(topic, (message) => {
      if (message.event === "state_updated" && message.payload && typeof message.payload === "object") {
        handler(message.payload as Record<string, unknown>);
      }
    });
  }

  onPresenceChange(topic: string, handler: (payload: { clientCount: number }) => void): () => void {
    return this.on("topicPresence", (payload) => {
      if (payload.topic === topic) {
        handler({ clientCount: payload.clientCount });
      }
    });
  }

  async clientCount(topic: string): Promise<number> {
    if (!this.transport.clientCount) {
      throw new Error("TransportError: clientCount is not supported by this transport");
    }
    return this.transport.clientCount(this.clientId, topic);
  }

  async reconnectOnce(attempt: number): Promise<void> {
    if (!this.reconnect.enabled || this.state === "destroyed") {
      return;
    }
    const delayMs = Math.min(this.reconnect.maxDelayMs, this.reconnect.initialDelayMs * this.reconnect.factor ** attempt);
    this.setState("reconnecting");
    this.events.emit("reconnecting", { attempt, delayMs });
    await new Promise((resolve) => setTimeout(resolve, delayMs));
    await this.connect();
  }
}

export function createClient(options: ClientOptions): CachePuppyClient {
  return new CachePuppyClient(options);
}
