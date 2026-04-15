# javascript_demo

Frontend-only demo for validating CachePuppy SDK usage against the managed Elixir websocket server.

## Purpose

- Exercise SDK lifecycle events.
- Exercise publish/subscribe message flow.
- Exercise per-topic shared state flow (`setTopicState`, `configureTopicWebhook`, `getTopicState`, `clearTopicState`, `state_updated`).
- Validate single cluster owner topic behavior across load-balanced backend nodes.

## Structure

- `webhook-server`: Minimal Node server that logs `POST /topic-state` JSON bodies (run this when demoing server-side webhook flush).
- `frontend`: Browser-style client simulation using the `cachepuppy-js-sdk` package (`file:` link to `sdk/javascript`).
- `interactive`: Vite + React browser app — join `sticky_notes_room`, share ephemeral `cursor_tracked` publishes (notes board only), and collaborative sticky notes in topic state.

## Interactive React demo (Sticky Notes Room)

1. Start Phoenix (same as below), e.g. `cd cachepuppy_core && mix phx.server`.
2. Build the SDK once (the app links it via `file:../../../sdk/javascript`):

   ```bash
   cd sdk/javascript && npm ci && npm run build
   ```

3. Run the UI:

   ```bash
   cd example/javascript_demo/interactive && npm ci && npm run dev
   ```

4. Open the printed local URL (usually `http://localhost:5173`). Enter a name and colour, connect, then move the pointer over the **sticky notes board** to publish `cursor_tracked` events; posting a note calls `setTopicState` with a `notes` list. Open a second browser window to see ghost cursors on the board and shared notes.

Optional: copy `.env.example` to `.env` and set `VITE_WS_URL` if your websocket endpoint differs from `ws://127.0.0.1:4000/socket/websocket`.

## Scenario (high level)

1. Frontend connects to websocket endpoint.
2. Frontend subscribes to a room topic and runs publish / presence / unsubscribe flows.
3. Frontend updates shared topic state; optional webhook receiver logs outbound flushes from the Elixir topic process.
4. Frontend calls `clearTopicState` and demonstrates read-after-clear failure.
5. Frontend disconnects.

# Demo Frontend Contract

`frontend` runs a small Node script that uses `cachepuppy-js-sdk` against a live Phoenix server (`transport: "phoenix"`).

## Scenario

1. Optional HTTP probes call `GET /api/health` through the load balancer (expect mixed `node` values when multiple backends are behind nginx).
2. Five clients connect via **the same WS URL** (typically `ws://127.0.0.1:4000/socket/websocket` when using Docker Compose + nginx) and subscribe to topic `demo_room`. Live presence is logged for all five.
3. `eve` calls `unsubscribe(demo_room)` — leaves the topic (Phoenix channel leave); the room stays open for the other four. Presence on the remaining clients should move to four members.
4. `alice` calls `publish` — only the four remaining members should log `room_broadcast` (`eve` must not).
5. `alice` calls `configureTopicWebhook` with `flush: true`, `url` to the webhook server, and `frequency: 1` — starts a 1s tick. She calls `setTopicState` — marks state dirty; after the next tick the webhook terminal logs a POST. Repeating the **same** payload is idempotent (no extra `state_updated`). After waiting for a tick, a **changed** `setTopicState` updates subscribers; the following tick posts again.
6. `bob` calls `getTopicStateWithMeta` — returns the shared topic state map plus node metadata.
7. `alice` reports `clientCount` for `demo_room` (expect four), then calls `clearTopicState` on `demo_room` — server-side topic process shutdown. `bob` calling `getTopicState` afterward should fail with `topic_not_found`.
8. All clients `disconnect`.

## Run

**1) Start the webhook receiver (optional but needed to see HTTP flush logs)**

```bash
cd example/javascript_demo/webhook-server && npm start
```

**2) Start Phoenix** (pick one)

**Multi-node cluster + nginx (recommended for LB validation)**

1. `cd cachepuppy_core && docker compose up --build -d`
2. If Phoenix runs **in Docker**, the app must reach the webhook on your host, for example:
   - `WEBHOOK_URL=http://host.docker.internal:8765/topic-state` (Docker Desktop macOS/Windows), or
   - Add a compose service on the same network and use that hostname.

**Single local Phoenix (no Docker)**

1. `cd cachepuppy_core && mix phx.server`

**3) Build SDK + demo client**

From repo root:

```bash
(cd sdk/javascript && npm ci && npm run build) && (cd example/javascript_demo/frontend && npm ci && npm run build && npm start)
```

Environment overrides (optional):

- `API_BASE` — HTTP origin for health probes (default `http://127.0.0.1:4000`)
- `WS_URL` — WebSocket URL (default `ws://127.0.0.1:4000/socket/websocket`)
- `WEBHOOK_URL` — Topic-state webhook target (default `http://127.0.0.1:8765/topic-state`)
- `PORT` — Webhook server listen port when using `webhook-server` (default `8765`)
