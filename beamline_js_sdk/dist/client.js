import { createEnvelope, isEnvelope, nextId } from "./protocol.js";
import { MockTransport } from "./transport/mockTransport.js";
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
    requestTimeoutMs;
    clientId;
    topicHandlers = new Map();
    pending = new Map();
    unlistenEnvelope;
    constructor(options) {
        this.options = options;
        this.transport = new MockTransport();
        this.reconnect = { ...DEFAULT_RECONNECT, ...(options.reconnect ?? {}) };
        this.requestTimeoutMs = options.requestTimeoutMs ?? 5_000;
        this.clientId = `client_${Date.now()}_${Math.floor(Math.random() * 10000)}`;
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
        if (message.type === "response" && message.correlationId) {
            const pending = this.pending.get(message.correlationId);
            if (pending) {
                clearTimeout(pending.timer);
                this.pending.delete(message.correlationId);
                if (message.ok === false) {
                    pending.reject(new Error(message.error ?? "Request failed"));
                }
                else {
                    pending.resolve(message);
                }
            }
            return;
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
    async subscribe(topic, handler) {
        if (!this.topicHandlers.has(topic)) {
            this.topicHandlers.set(topic, new Set());
            if (this.state === "connected") {
                await this.transport.sendEnvelope(this.clientId, createEnvelope({ type: "subscribe", topic }));
            }
        }
        this.topicHandlers.get(topic).add(handler);
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
    request(topic, action, payload, timeoutMs = this.requestTimeoutMs) {
        const correlationId = nextId("req");
        const requestMsg = createEnvelope({
            type: "request",
            topic,
            event: action,
            payload,
            correlationId,
            meta: { clientId: this.clientId },
        });
        const promise = new Promise((resolve, reject) => {
            const timer = setTimeout(() => {
                this.pending.delete(correlationId);
                reject(new Error(`TimeoutError: request timed out (${correlationId})`));
            }, timeoutMs);
            this.pending.set(correlationId, { resolve, reject, timer });
        });
        void this.transport.sendEnvelope(this.clientId, requestMsg);
        return promise;
    }
    async respond(correlationId, ok, payload, error) {
        await this.transport.sendEnvelope(this.clientId, createEnvelope({
            type: "response",
            correlationId,
            ok,
            payload,
            error,
        }));
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
