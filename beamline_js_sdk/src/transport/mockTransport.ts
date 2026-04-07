import type { BeamlineEnvelope } from "../types.js";
import type { Transport } from "./transport.js";

type EnvelopeHandler = (message: BeamlineEnvelope) => void;

class MockBus {
  private envelopeHandlers = new Map<string, Set<EnvelopeHandler>>();
  private topicMembers = new Map<string, Set<string>>();

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

  sendEnvelope(senderId: string, message: BeamlineEnvelope): void {
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

}

const globalBus = new MockBus();

export class MockTransport implements Transport {
  async connect(clientId: string): Promise<void> {
    globalBus.connect(clientId);
  }

  async disconnect(clientId: string): Promise<void> {
    globalBus.disconnect(clientId);
  }

  async sendEnvelope(clientId: string, message: BeamlineEnvelope): Promise<void> {
    globalBus.sendEnvelope(clientId, message);
  }

  onEnvelope(clientId: string, handler: EnvelopeHandler): () => void {
    return globalBus.onEnvelope(clientId, handler);
  }

  async clientCount(_clientId: string, topic: string): Promise<number> {
    return globalBus.clientCount(topic);
  }

}
