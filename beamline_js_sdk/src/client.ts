import { createEnvelope, isEnvelope } from "./protocol.js";
import { MockTransport } from "./transport/mockTransport.js";
import { PhoenixTransport } from "./transport/phoenixTransport.js";
import type { Transport } from "./transport/transport.js";
import type {
  BeamlineEnvelope,
  ClientEventMap,
  ClientOptions,
  ConnectionState,
  ReconnectConfig,
  TopicHandler,
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

export class BeamlineClient {
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

  private handleEnvelope(message: BeamlineEnvelope): void {
    if (!isEnvelope(message)) {
      this.events.emit("error", new Error("ProtocolError: invalid envelope"));
      return;
    }
    this.events.emit("message", message);

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

export function createClient(options: ClientOptions): BeamlineClient {
  return new BeamlineClient(options);
}
