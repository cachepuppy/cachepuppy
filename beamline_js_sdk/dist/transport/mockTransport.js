class MockBus {
    envelopeHandlers = new Map();
    topicMembers = new Map();
    connect(clientId) {
        if (!this.envelopeHandlers.has(clientId)) {
            this.envelopeHandlers.set(clientId, new Set());
        }
    }
    disconnect(clientId) {
        this.envelopeHandlers.delete(clientId);
        for (const members of this.topicMembers.values()) {
            members.delete(clientId);
        }
    }
    onEnvelope(clientId, handler) {
        this.connect(clientId);
        const set = this.envelopeHandlers.get(clientId);
        set.add(handler);
        return () => set.delete(handler);
    }
    sendEnvelope(senderId, message) {
        if (message.type === "subscribe" && message.topic) {
            if (!this.topicMembers.has(message.topic)) {
                this.topicMembers.set(message.topic, new Set());
            }
            this.topicMembers.get(message.topic).add(senderId);
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
            const allowed = new Set(Array.isArray(rawIds) ? rawIds.filter((id) => typeof id === "string") : []);
            const members = this.topicMembers.get(message.topic);
            if (!members || allowed.size === 0) {
                return;
            }
            const outMeta = { ...(message.meta ?? {}) };
            delete outMeta.clientIds;
            outMeta.clientId = senderId;
            const outbound = {
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
    clientCount(topic) {
        const members = this.topicMembers.get(topic);
        if (!members) {
            return 0;
        }
        return members.size;
    }
}
const globalBus = new MockBus();
export class MockTransport {
    async connect(clientId) {
        globalBus.connect(clientId);
    }
    async disconnect(clientId) {
        globalBus.disconnect(clientId);
    }
    async sendEnvelope(clientId, message) {
        globalBus.sendEnvelope(clientId, message);
    }
    onEnvelope(clientId, handler) {
        return globalBus.onEnvelope(clientId, handler);
    }
    async clientCount(_clientId, topic) {
        return globalBus.clientCount(topic);
    }
}
