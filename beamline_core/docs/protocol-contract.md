# Beamline Protocol Contract (Shared)

This is the backend-facing mirror of the wire protocol defined in `beamline_js_sdk/docs/api-design.md`.

No Phoenix runtime is implemented in this phase.

## Transport target

- Primary target: websocket endpoint in a future Phoenix app.
- Transport-specific details (path, params, heartbeat) are deferred.
- Message semantics are fixed here so JS SDK and backend can evolve independently.

## Envelope

```json
{
  "v": 1,
  "type": "request",
  "id": "msg_123",
  "topic": "orders",
  "event": "get",
  "payload": { "orderId": "o1" },
  "ts": 1770000000000,
  "correlationId": null,
  "ok": null,
  "error": null,
  "meta": { "clientId": "web-1" }
}
```

## Message types

- `subscribe`: register interest in `topic`
- `unsubscribe`: remove interest in `topic`
- `publish`: fire event to topic subscribers
- `request`: directed request expecting `response`
- `response`: response to prior request using `correlationId`
- `system`: optional informational/system events

## Validation rules

- Reject envelopes with unsupported `v`.
- Require `id` for all non-system messages.
- Require `topic` for `subscribe`, `unsubscribe`, `publish`, `request`.
- Require `correlationId` for `response`.
- For `response`, exactly one of `payload` or `error` should be populated.

## Backend mapping notes (future Phoenix)

- Phoenix Channel topic names map directly to `topic`.
- Incoming websocket payload parses to this envelope.
- Channel broadcasts can emit `publish` envelopes.
- Channel handles can service `request` and answer with `response`.

## TODO for Elixir implementation phase

- Define endpoint path and auth params.
- Add serializer/deserializer module for envelope validation.
- Implement channel process routing for topics/events.
- Implement request timeout semantics compatible with JS SDK.
