import { Socket, type Channel } from "phoenix";
import type { CachePuppyEnvelope } from "../types.js";
import type { TopicStateResponse, Transport } from "./transport.js";

type EnvelopeHandler = (message: CachePuppyEnvelope) => void;

function toChannelTopic(topic: string): string {
  return topic.startsWith("events:") ? topic : `events:${topic}`;
}

function toSdkTopic(channelTopic: string): string {
  return channelTopic.startsWith("events:") ? channelTopic.slice("events:".length) : channelTopic;
}

function toSocketPath(url: string): string {
  return url.endsWith("/websocket") ? url.slice(0, -"/websocket".length) : url;
}

export class PhoenixTransport implements Transport {
  private socket?: Socket;
  private handlers = new Map<string, Set<EnvelopeHandler>>();
  private channels = new Map<string, Channel>();
  private channelReady = new Map<string, Promise<Channel>>();
  private joinMetaByKey = new Map<string, Record<string, unknown>>();

  constructor(
    private readonly baseUrl: string,
    private readonly authToken?: string,
    private readonly customClientId?: string,
  ) {}

  async connect(_clientId: string): Promise<void> {
    const clientId = this.customClientId ?? _clientId;
    this.socket = new Socket(toSocketPath(this.baseUrl), {
      params: {
        ...(this.authToken ? { token: this.authToken } : {}),
        client_id: clientId,
      },
    });
    this.socket.connect();
  }

  async disconnect(_clientId: string): Promise<void> {
    const clientId = this.customClientId ?? _clientId;
    for (const channelTopic of this.channels.keys()) {
      this.joinMetaByKey.delete(joinMetaKey(clientId, channelTopic));
    }
    for (const channel of this.channels.values()) {
      channel.leave();
    }
    this.channels.clear();
    this.channelReady.clear();
    this.socket?.disconnect();
    this.socket = undefined;
  }

  private emit(clientId: string, message: CachePuppyEnvelope): void {
    const set = this.handlers.get(clientId);
    if (!set) {
      return;
    }
    for (const handler of set.values()) {
      handler(message);
    }
  }

  private ensureChannel(clientId: string, topic: string): Promise<Channel> {
    const channelTopic = toChannelTopic(topic);
    const existingReady = this.channelReady.get(channelTopic);
    if (existingReady) {
      return existingReady;
    }
    if (!this.socket) {
      throw new Error("TransportError: socket is not connected");
    }

    const channel = this.socket.channel(channelTopic, {});
    channel.on("message", (payload: Record<string, unknown>) => {
      const payloadMeta =
        payload.meta && typeof payload.meta === "object" ? (payload.meta as Record<string, unknown>) : {};

      const message: CachePuppyEnvelope = {
        v: 1,
        type: "publish",
        id: `srv_${Date.now()}`,
        topic: typeof payload.topic === "string" ? payload.topic : toSdkTopic(channelTopic),
        event: typeof payload.event === "string" ? payload.event : "message",
        payload: payload.payload,
        ts: typeof payload.ts === "number" ? payload.ts : Date.now(),
        meta: { transport: "phoenix", ...payloadMeta },
      };
      this.emit(clientId, message);
    });

    this.channels.set(channelTopic, channel);
    const resolvedClientId = this.customClientId ?? clientId;
    const ready = new Promise<Channel>((resolve, reject) => {
      channel
        .join()
        .receive("ok", (payload?: unknown) => {
          if (payload && typeof payload === "object" && !Array.isArray(payload)) {
            this.joinMetaByKey.set(joinMetaKey(resolvedClientId, channelTopic), payload as Record<string, unknown>);
          }
          resolve(channel);
        })
        .receive("error", () => {
          this.emit(clientId, {
            v: 1,
            type: "system",
            id: `err_${Date.now()}`,
            topic: toSdkTopic(channelTopic),
            event: "join_error",
            payload: null,
            ts: Date.now(),
            meta: { transport: "phoenix" },
          });
          reject(new Error(`Failed to join topic ${channelTopic}`));
        });
    });
    this.channelReady.set(channelTopic, ready);
    return ready;
  }

  async sendEnvelope(clientId: string, message: CachePuppyEnvelope): Promise<void> {
    if (message.type === "subscribe" && message.topic) {
      await this.ensureChannel(clientId, message.topic);
      return;
    }

    if (message.type === "unsubscribe" && message.topic) {
      const channelTopic = toChannelTopic(message.topic);
      const resolvedClientId = this.customClientId ?? clientId;
      this.joinMetaByKey.delete(joinMetaKey(resolvedClientId, channelTopic));
      const channel = this.channels.get(channelTopic);
      if (channel) {
        channel.leave();
        this.channels.delete(channelTopic);
        this.channelReady.delete(channelTopic);
      }
      return;
    }

    if (message.type === "publish" && message.topic) {
      const channel = await this.ensureChannel(clientId, message.topic);
      await new Promise<void>((resolve, reject) => {
        channel
          .push("publish", {
            event: message.event,
            payload: message.payload,
          })
          .receive("ok", () => resolve())
          .receive("error", () => reject(new Error("Failed to publish message")));
      });
      return;
    }

    if (message.type === "publish_to" && message.topic) {
      const rawIds = message.meta?.clientIds;
      const clientIds = Array.isArray(rawIds) ? rawIds.filter((id): id is string => typeof id === "string") : [];
      const channel = await this.ensureChannel(clientId, message.topic);
      await new Promise<void>((resolve, reject) => {
        channel
          .push("publish_to", {
            event: message.event,
            payload: message.payload,
            client_ids: clientIds,
          })
          .receive("ok", () => resolve())
          .receive("error", () => reject(new Error("Failed to publish_to message")))
          .receive("timeout", () => reject(new Error("Timed out while publishing to subset")));
      });
      return;
    }
  }

  onEnvelope(clientId: string, handler: EnvelopeHandler): () => void {
    if (!this.handlers.has(clientId)) {
      this.handlers.set(clientId, new Set());
    }
    const set = this.handlers.get(clientId)!;
    set.add(handler);
    return () => set.delete(handler);
  }

  async clientCount(clientId: string, topic: string): Promise<number> {
    const channel = await this.ensureChannel(clientId, topic);
    return new Promise<number>((resolve, reject) => {
      channel
        .push("client_count", {})
        .receive("ok", (payload?: unknown) => {
          const data = (payload ?? {}) as { client_count?: unknown };
          const n = data.client_count;
          resolve(typeof n === "number" && Number.isFinite(n) ? Math.floor(n) : 0);
        })
        .receive("error", () => reject(new Error("Failed to get client count")))
        .receive("timeout", () => reject(new Error("Timed out while getting client count")));
    });
  }

  async setState(clientId: string, topic: string, payload: Record<string, unknown>): Promise<Record<string, unknown>> {
    const channel = await this.ensureChannel(clientId, topic);

    return new Promise<Record<string, unknown>>((resolve, reject) => {
      channel
        .push("set_state", { payload })
        .receive("ok", (response?: unknown) => {
          const data = (response ?? {}) as { state?: unknown };
          resolve(asRecord(data.state));
        })
        .receive("error", () => reject(new Error("Failed to set topic state")))
        .receive("timeout", () => reject(new Error("Timed out while setting topic state")));
    });
  }

  async getState(clientId: string, topic: string): Promise<Record<string, unknown>> {
    const response = await this.getStateWithMeta(clientId, topic);
    return response.state;
  }

  async getStateWithMeta(clientId: string, topic: string): Promise<TopicStateResponse> {
    const channel = await this.ensureChannel(clientId, topic);

    return new Promise<TopicStateResponse>((resolve, reject) => {
      channel
        .push("get_state", {})
        .receive("ok", (response?: unknown) => {
          const data = (response ?? {}) as { state?: unknown; meta?: unknown };
          const meta = asRecord(data.meta);
          const sourceNode = typeof meta.source_node === "string" ? meta.source_node : undefined;
          const servedByNode = typeof meta.served_by_node === "string" ? meta.served_by_node : undefined;
          resolve({ state: asRecord(data.state), sourceNode, servedByNode });
        })
        .receive("error", () => reject(new Error("Failed to get topic state")))
        .receive("timeout", () => reject(new Error("Timed out while getting topic state")));
    });
  }

  getChannelJoinMeta(clientId: string, topic: string): Record<string, unknown> | undefined {
    const channelTopic = toChannelTopic(topic);
    const resolvedClientId = this.customClientId ?? clientId;
    return this.joinMetaByKey.get(joinMetaKey(resolvedClientId, channelTopic));
  }

  async closeTopic(clientId: string, topic: string): Promise<boolean> {
    const channel = await this.ensureChannel(clientId, topic);

    return new Promise<boolean>((resolve, reject) => {
      channel
        .push("close_topic", {})
        .receive("ok", (response?: unknown) => {
          const data = (response ?? {}) as { closed?: unknown };
          resolve(data.closed === true);
        })
        .receive("error", () => reject(new Error("Failed to close topic")))
        .receive("timeout", () => reject(new Error("Timed out while closing topic")));
    });
  }
}

function asRecord(value: unknown): Record<string, unknown> {
  if (value && typeof value === "object" && !Array.isArray(value)) {
    return value as Record<string, unknown>;
  }

  return {};
}

function joinMetaKey(clientId: string, channelTopic: string): string {
  return `${clientId}::${channelTopic}`;
}
