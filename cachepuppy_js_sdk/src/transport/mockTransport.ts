import type { CachePuppyEnvelope } from "../types.js";
import type { TopicStateResponse, Transport } from "./transport.js";

type EnvelopeHandler = (message: CachePuppyEnvelope) => void;

class MockBus {
  private envelopeHandlers = new Map<string, Set<EnvelopeHandler>>();
  private topicMembers = new Map<string, Set<string>>();
  private topicStates = new Map<string, Record<string, unknown>>();

  connect(clientId: string): void {
    if (!this.envelopeHandlers.has(clientId)) {
      this.envelopeHandlers.set(clientId, new Set());
    }
  }

  disconnect(clientId: string): void {
    this.envelopeHandlers.delete(clientId);
    for (const members of this.topicMembers.values()) {
      members.delete(clientId);
    }
  }

  onEnvelope(clientId: string, handler: EnvelopeHandler): () => void {
    this.connect(clientId);
    const set = this.envelopeHandlers.get(clientId)!;
    set.add(handler);
    return () => set.delete(handler);
  }

  sendEnvelope(senderId: string, message: CachePuppyEnvelope): void {
    if (message.type === "subscribe" && message.topic) {
      if (!this.topicMembers.has(message.topic)) {
        this.topicMembers.set(message.topic, new Set());
      }
      this.topicMembers.get(message.topic)!.add(senderId);
      return;
    }

    if (message.type === "unsubscribe" && message.topic) {
      this.topicMembers.get(message.topic)?.delete(senderId);
      return;
    }

    if (message.type === "publish" && message.topic) {
      const members = this.topicMembers.get(message.topic);
      if (!members) {
        return;
      }
      for (const memberId of members.values()) {
        const handlers = this.envelopeHandlers.get(memberId);
        if (!handlers) {
          continue;
        }
        for (const handler of handlers.values()) {
          handler(message);
        }
      }
      return;
    }

    if (message.type === "publish_to" && message.topic) {
      const rawIds = message.meta?.clientIds;
      const allowed = new Set(Array.isArray(rawIds) ? rawIds.filter((id): id is string => typeof id === "string") : []);
      const members = this.topicMembers.get(message.topic);
      if (!members || allowed.size === 0) {
        return;
      }
      const outMeta: Record<string, unknown> = { ...(message.meta ?? {}) };
      delete outMeta.clientIds;
      outMeta.clientId = senderId;
      const outbound: CachePuppyEnvelope = {
        v: 1,
        type: "publish",
        id: message.id,
        topic: message.topic,
        event: message.event,
        payload: message.payload,
        ts: message.ts,
        meta: outMeta,
      };
      for (const memberId of members.values()) {
        if (!allowed.has(memberId)) {
          continue;
        }
        const handlers = this.envelopeHandlers.get(memberId);
        if (!handlers) {
          continue;
        }
        for (const handler of handlers.values()) {
          handler(outbound);
        }
      }
      return;
    }

    // Non-topic messages are broadcast in mock mode.
    for (const handlers of this.envelopeHandlers.values()) {
      for (const handler of handlers.values()) {
        handler(message);
      }
    }
  }

  clientCount(topic: string): number {
    const members = this.topicMembers.get(topic);
    if (!members) {
      return 0;
    }
    return members.size;
  }

  setState(senderId: string, topic: string, payload: Record<string, unknown>): Record<string, unknown> {
    const next = { ...payload };
    this.topicStates.set(topic, next);

    const members = this.topicMembers.get(topic);
    if (members) {
      const message: CachePuppyEnvelope = {
        v: 1,
        type: "publish",
        id: `state_${Date.now()}`,
        topic,
        event: "state_updated",
        payload: next,
        ts: Date.now(),
        meta: { clientId: senderId, transport: "mock" },
      };

      for (const memberId of members.values()) {
        const handlers = this.envelopeHandlers.get(memberId);
        if (!handlers) {
          continue;
        }

        for (const handler of handlers.values()) {
          handler(message);
        }
      }
    }

    return next;
  }

  getState(topic: string): Record<string, unknown> {
    return { ...(this.topicStates.get(topic) ?? {}) };
  }

  closeTopic(topic: string): boolean {
    const hadTopic = this.topicStates.has(topic) || this.topicMembers.has(topic);
    this.topicStates.delete(topic);
    this.topicMembers.delete(topic);
    return hadTopic;
  }

}

const globalBus = new MockBus();

export class MockTransport implements Transport {
  async connect(clientId: string): Promise<void> {
    globalBus.connect(clientId);
  }

  async disconnect(clientId: string): Promise<void> {
    globalBus.disconnect(clientId);
  }

  async sendEnvelope(clientId: string, message: CachePuppyEnvelope): Promise<void> {
    globalBus.sendEnvelope(clientId, message);
  }

  onEnvelope(clientId: string, handler: EnvelopeHandler): () => void {
    return globalBus.onEnvelope(clientId, handler);
  }

  async clientCount(_clientId: string, topic: string): Promise<number> {
    return globalBus.clientCount(topic);
  }

  async setState(clientId: string, topic: string, payload: Record<string, unknown>): Promise<Record<string, unknown>> {
    return globalBus.setState(clientId, topic, payload);
  }

  async getState(_clientId: string, topic: string): Promise<Record<string, unknown>> {
    return globalBus.getState(topic);
  }

  async getStateWithMeta(_clientId: string, topic: string): Promise<TopicStateResponse> {
    return { state: globalBus.getState(topic), sourceNode: "mock", servedByNode: "mock" };
  }

  async closeTopic(_clientId: string, topic: string): Promise<boolean> {
    return globalBus.closeTopic(topic);
  }

}
