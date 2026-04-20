# CachePuppy JS SDK API Design

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
  clientId: "frontend_user_123",
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
- `clientCount(topic: string): Promise<number>`
- `setData(table, key, value, options?)` / `getData(table, key)` / `deleteData(table, key)` — cache operations over websocket (`session` channel events `set_cache_data`, `get_cache_data`, `delete_cache_data`).

### Topic shared state vs connection session state

- `setTopicState(topic, payload)` / `getTopicState(topic)` / `getTopicStateWithMeta(topic)` / `clearTopicState(topic)` — cluster-wide shared state for the topic; subscribers receive `state_updated` only when the stored map actually changes.
- `configureTopicWebhook(topic, { flush, url?, frequency? })` — enable or disable periodic webhook POSTs of `{ topic, state, ts }` on a timer when state has changed (`configure_topic_webhook` on the channel). `clearTopicState` stops the topic process server-side (Phoenix `close_topic` push).
- `setSessionState(payload)` / `getSessionState()` — private state on the Phoenix `session` channel (no room topic); other clients do not see it; reconnect starts empty.
- Cache websocket calls (`setData/getData/deleteData`) also use the `session` channel and mirror `/api/cache/*` semantics.

### Event APIs

- `on("connected" | "disconnected" | "reconnecting" | "stateChange", handler)`
- `on("message", handler)` for all decoded protocol messages.
- `on("error", handler)` for typed SDK errors.

## Admin HTTP client (`CachePuppyAdminClient`)

Use **`createAdminClient(options)`** when calling the server’s **HTTP** routes from Node or a backend (no websocket, no `connect()`). Same **`url`** convention as `createClient`: a Phoenix websocket URL; the SDK derives the HTTP origin (see `httpBaseUrl.ts`).

### Options

- `url` (required): websocket URL used only to compute the HTTP base.
- `authToken` (optional): sent as `Authorization: Bearer …` when present.
- `fetchImpl` (optional): override `fetch` (tests, polyfills).

### Methods

- `setTopicState(topic, state)` — `PUT /api/server/v1/topics/:topic/state`; body is the full state object; returns updated `state` from the response.
- `getTopicState(topic)` — `GET …/state`; returns the `state` map.
- `getTopicStateWithMeta(topic)` — same GET; returns `{ state, sourceNode?, servedByNode? }` (from `meta.source_node` / `meta.served_by_node`).
- `clearTopicState(topic)` — `DELETE …/topics/:topic`; returns `closed` as boolean.
- `sendTopicMessage(topic, { event, payload? })` — `POST …/messages`; expects **202**; no return value.
- `getTopicPresence(topic)` — `GET …/presence`; returns `{ clientCount, presence }` (maps `client_count` from JSON).
- `setData(table, key, value, options?)` — `POST /api/cache/setdata`; returns stored `value`.
- `getData(table, key)` — `POST /api/cache/getdata`; returns `value` (or `undefined` if not found/expired).
- `deleteData(table, key)` — `POST /api/cache/deletedata`; returns `deleted` as boolean.

Non-success HTTP responses throw `Error` with status and optional `reason` from JSON.

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

- `CachePuppyError` (base)
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
