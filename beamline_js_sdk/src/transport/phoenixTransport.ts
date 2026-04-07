import { Socket, type Channel } from "phoenix";
import type { BeamlineEnvelope } from "../types.js";
import type { Transport } from "./transport.js";

type EnvelopeHandler = (message: BeamlineEnvelope) => void;

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

  constructor(private readonly baseUrl: string, private readonly authToken?: string) {}

  async connect(_clientId: string): Promise<void> {
    this.socket = new Socket(toSocketPath(this.baseUrl), {
      params: this.authToken ? { token: this.authToken } : {},
    });
    this.socket.connect();
  }

  async disconnect(_clientId: string): Promise<void> {
    for (const channel of this.channels.values()) {
      channel.leave();
    }
    this.channels.clear();
    this.socket?.disconnect();
    this.socket = undefined;
  }

  private emit(clientId: string, message: BeamlineEnvelope): void {
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
      const message: BeamlineEnvelope = {
        v: 1,
        type: "publish",
        id: `srv_${Date.now()}`,
        topic: typeof payload.topic === "string" ? payload.topic : toSdkTopic(channelTopic),
        event: typeof payload.event === "string" ? payload.event : "message",
        payload: payload.payload,
        ts: typeof payload.ts === "number" ? payload.ts : Date.now(),
        meta: { transport: "phoenix" },
      };
      this.emit(clientId, message);
    });

    this.channels.set(channelTopic, channel);
    const ready = new Promise<Channel>((resolve, reject) => {
      channel
        .join()
        .receive("ok", () => resolve(channel))
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

  async sendEnvelope(clientId: string, message: BeamlineEnvelope): Promise<void> {
    if (message.type === "subscribe" && message.topic) {
      await this.ensureChannel(clientId, message.topic);
      return;
    }

    if (message.type === "unsubscribe" && message.topic) {
      const channelTopic = toChannelTopic(message.topic);
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
  }

  onEnvelope(clientId: string, handler: EnvelopeHandler): () => void {
    if (!this.handlers.has(clientId)) {
      this.handlers.set(clientId, new Set());
    }
    const set = this.handlers.get(clientId)!;
    set.add(handler);
    return () => set.delete(handler);
  }
}
