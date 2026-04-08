# cachepuppy_core

`cachepuppy_core` is the Phoenix websocket backend for CachePuppy.

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
- Optional connect param: `client_id` for custom client identity labels.

Supported inbound events:

- `"publish"` with payload `%{"event" => "...", "payload" => ...}`
- `"publish_to"` with payload `%{"event" => "...", "payload" => ..., "client_ids" => [...]}` (only those Presence keys receive the outbound `message`)
- `"message"` envelope with `%{"type" => "publish", "event" => "...", "payload" => ...}`
- `"client_count"` returns `%{"client_count" => integer}` for the current topic (Presence member count).

Broadcast behavior:

- Server broadcasts `"message"` events to all subscribers on the channel topic.
- Outbound message shape follows the CachePuppy envelope fields (`v`, `type`, `topic`, `event`, `payload`, `ts`, `meta`).
