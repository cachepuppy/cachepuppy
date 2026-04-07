# beamline_core

`beamline_core` is the Phoenix websocket backend for Beamline.

This version is intentionally auth-free and focused on core realtime behavior.

## Local run

- `mix setup`
- `mix phx.server`

Server runs on `http://localhost:4000`.

## HTTP endpoint

- `GET /api/health` returns a basic status payload.

## Websocket endpoint

- Socket path: `/socket/websocket`
- Channel topic format: `events:<topic_name>`

Supported inbound events:

- `"publish"` with payload `%{"event" => "...", "payload" => ...}`
- `"message"` envelope with `%{"type" => "publish", "event" => "...", "payload" => ...}`

Broadcast behavior:

- Server broadcasts `"message"` events to all subscribers on the channel topic.
- Outbound message shape follows the Beamline envelope fields (`v`, `type`, `topic`, `event`, `payload`, `ts`).
