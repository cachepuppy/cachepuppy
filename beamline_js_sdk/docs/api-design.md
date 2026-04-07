# Beamline JS SDK API Design

This document defines the SDK API first, before any Elixir engine implementation.

## Design goals

- Work for Node.js and browser JavaScript developers.
- Expose simple topic-based event semantics over websocket.
- Keep transport pluggable so Phoenix transport can be added later.
- Use versioned wire envelopes and explicit error classes.

## Public API (proposed)

### Client creation

```ts
const client = createClient({
  url: "ws://localhost:4000/socket/websocket",
  authToken: "token-123",
  getAuthToken: async () => "token-rotated",
  reconnect: {
    enabled: true,
    initialDelayMs: 500,
    maxDelayMs: 10_000,
    factor: 2,
  },
  transport: "mock", // default for now
});
```

### Lifecycle

- `connect(): Promise<void>`
- `disconnect(reason?: string): Promise<void>`
- `destroy(): Promise<void>`
- `getState(): ConnectionState`

States: `idle | connecting | connected | reconnecting | disconnected | destroyed`

### Generic topic APIs

- `subscribe(topic: string, handler: TopicHandler): Promise<Unsubscribe>`
- `unsubscribe(topic: string, handler?: TopicHandler): Promise<void>`
- `publish(topic: string, event: string, payload: unknown): Promise<void>`

### Event APIs

- `on("connected" | "disconnected" | "reconnecting" | "stateChange", handler)`
- `on("message", handler)` for all decoded protocol messages.
- `on("error", handler)` for typed SDK errors.

## Wire envelope (v1)

All protocol messages use JSON:

```json
{
  "v": 1,
  "type": "publish",
  "id": "msg_123",
  "topic": "orders",
  "event": "created",
  "payload": { "orderId": "o1" },
  "ts": 1770000000000,
  "meta": { "clientId": "web-1" }
}
```

Required fields by message type:

- `subscribe`: `topic`
- `unsubscribe`: `topic`
- `publish`: `topic`, `event`, `payload`

## Error taxonomy

- `BeamlineError` (base)
- `ConnectionError` (connect/disconnect transport failures)
- `ProtocolError` (invalid envelope or unsupported version)
- `AuthError` (token missing/invalid/refresh failed)
- `TransportError` (transport implementation specific)

## Reconnect behavior

- Reconnect only if `reconnect.enabled === true` and client not destroyed.
- Exponential backoff: `delay = min(maxDelayMs, initialDelayMs * factor^attempt)`.
- Emit `reconnecting` and `stateChange` per attempt.
- Re-subscribe previously subscribed topics after reconnect.

## Auth behavior

- `authToken` is used initially if provided.
- `getAuthToken` is called before (re)connect if present.
- If token retrieval fails, emit `AuthError` and do not connect.

## Forward compatibility

- Envelope is versioned with `v`.
- Unknown fields are tolerated.
- Unknown message `type` emits `ProtocolError` but does not crash client.
