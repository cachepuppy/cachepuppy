import { nextId } from "../protocol.js";
import type { CachePuppyEnvelope } from "../types.js";
import type { TopicStateResponse, Transport } from "./transport.js";

type EnvelopeHandler = (message: CachePuppyEnvelope) => void;

class MockBus {
  private envelopeHandlers = new Map<string, Set<EnvelopeHandler>>();
  private topicMembers = new Map<string, Set<string>>();
  private topicStates = new Map<string, Record<string, unknown>>();
  /** Per simulated client (private session channel; no room topic). */
  private sessionStates = new Map<string, Record<string, unknown>>();

  connect(clientId: string): void {
    if (!this.envelopeHandlers.has(clientId)) {
      this.envelopeHandlers.set(clientId, new Set());
    }
  }

  disconnect(clientId: string): void {
    const affectedTopics: string[] = [];
    for (const [topic, members] of this.topicMembers.entries()) {
      if (members.has(clientId)) {
        affectedTopics.push(topic);
        members.delete(clientId);
      }
    }
    for (const topic of affectedTopics) {
      this.broadcastPresenceChange(topic);
    }
    this.sessionStates.delete(clientId);
    this.envelopeHandlers.delete(clientId);
  }

  private broadcastPresenceChange(topic: string): void {
    const members = this.topicMembers.get(topic);
    const clientCount = members?.size ?? 0;
    const envelope: CachePuppyEnvelope = {
      v: 1,
      type: "system",
      id: nextId("presence"),
      topic,
      event: "presence_change",
      payload: { clientCount },
      ts: Date.now(),
      meta: { transport: "mock" },
    };
    if (!members || members.size === 0) {
      return;
    }
    for (const memberId of members.values()) {
      const handlers = this.envelopeHandlers.get(memberId);
      if (!handlers) {
        continue;
      }
      for (const handler of handlers.values()) {
        handler(envelope);
      }
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
      this.broadcastPresenceChange(message.topic);
      return;
    }

    if (message.type === "unsubscribe" && message.topic) {
      this.topicMembers.get(message.topic)?.delete(senderId);
      this.broadcastPresenceChange(message.topic);
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

  setSessionState(clientId: string, payload: Record<string, unknown>): Record<string, unknown> {
    const next = { ...payload };
    this.sessionStates.set(clientId, next);
    return next;
  }

  getSessionState(clientId: string): Record<string, unknown> {
    return { ...(this.sessionStates.get(clientId) ?? {}) };
  }

  clearTopicState(topic: string): boolean {
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

  async clearTopicState(_clientId: string, topic: string): Promise<boolean> {
    return globalBus.clearTopicState(topic);
  }

  async setSessionState(clientId: string, payload: Record<string, unknown>): Promise<Record<string, unknown>> {
    return globalBus.setSessionState(clientId, payload);
  }

  async getSessionState(clientId: string): Promise<Record<string, unknown>> {
    return globalBus.getSessionState(clientId);
  }

  getChannelJoinMeta(_clientId: string, _topic: string): Record<string, unknown> | undefined {
    return undefined;
  }

}
