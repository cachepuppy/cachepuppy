import { createEnvelope, isEnvelope } from "./protocol.js";
import { MockTransport } from "./transport/mockTransport.js";
import { PhoenixTransport } from "./transport/phoenixTransport.js";
class TypedEventBus {
    handlers = new Map();
    on(event, handler) {
        if (!this.handlers.has(event)) {
            this.handlers.set(event, new Set());
        }
        const set = this.handlers.get(event);
        set.add(handler);
        return () => set.delete(handler);
    }
    emit(event, payload) {
        const set = this.handlers.get(event);
        if (!set) {
            return;
        }
        for (const handler of set.values()) {
            handler(payload);
        }
    }
}
const DEFAULT_RECONNECT = {
    enabled: true,
    initialDelayMs: 500,
    maxDelayMs: 10_000,
    factor: 2,
};
export class BeamlineClient {
    options;
    state = "idle";
    events = new TypedEventBus();
    transport;
    reconnect;
    clientId;
    topicHandlers = new Map();
    unlistenEnvelope;
    constructor(options) {
        this.options = options;
        this.transport =
            options.transport === "mock"
                ? new MockTransport()
                : new PhoenixTransport(options.url, options.authToken, options.clientId);
        this.reconnect = { ...DEFAULT_RECONNECT, ...(options.reconnect ?? {}) };
        this.clientId = options.clientId ?? `client_${Date.now()}_${Math.floor(Math.random() * 10000)}`;
    }
    setState(state) {
        this.state = state;
        this.events.emit("stateChange", { state });
    }
    getState() {
        return this.state;
    }
    on = this.events.on.bind(this.events);
    async connect() {
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
    async disconnect(reason) {
        if (this.state === "destroyed") {
            return;
        }
        await this.transport.disconnect(this.clientId);
        this.unlistenEnvelope?.();
        this.setState("disconnected");
        this.events.emit("disconnected", { reason });
    }
    async destroy() {
        await this.disconnect("destroy");
        this.setState("destroyed");
    }
    handleEnvelope(message) {
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
    async subscribe(topic, handler) {
        const isNewTopic = !this.topicHandlers.has(topic);
        if (isNewTopic) {
            this.topicHandlers.set(topic, new Set());
        }
        this.topicHandlers.get(topic).add(handler);
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
    async unsubscribe(topic) {
        this.topicHandlers.delete(topic);
        await this.transport.sendEnvelope(this.clientId, createEnvelope({ type: "unsubscribe", topic }));
    }
    async publish(topic, event, payload) {
        await this.transport.sendEnvelope(this.clientId, createEnvelope({ type: "publish", topic, event, payload }));
    }
    async publishTo(topic, event, payload, clientIds) {
        await this.transport.sendEnvelope(this.clientId, createEnvelope({
            type: "publish_to",
            topic,
            event,
            payload,
            meta: { clientIds },
        }));
    }
    async clientCount(topic) {
        if (!this.transport.clientCount) {
            throw new Error("TransportError: clientCount is not supported by this transport");
        }
        return this.transport.clientCount(this.clientId, topic);
    }
    async reconnectOnce(attempt) {
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
export function createClient(options) {
    return new BeamlineClient(options);
}
