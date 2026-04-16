# javascript_demo

Interactive React demo for validating CachePuppy SDK usage against the managed Elixir websocket server.

## Purpose

- Exercise SDK lifecycle events.
- Exercise publish/subscribe message flow.
- Exercise per-topic shared state flow (`setTopicState`, `configureTopicWebhook`, `getTopicState`, `clearTopicState`, `state_updated`).
- Validate single cluster owner topic behavior across load-balanced backend nodes.

## Structure

- `webhook-server`: Minimal Node server that logs `POST /topic-state` JSON bodies (run this when demoing server-side webhook flush).
- `interactive`: Vite + React browser app — uses `@cachepuppy/react` (backed by `cachepuppy-js-sdk`) to join `sticky_notes_room`, share ephemeral `cursor_tracked` publishes (notes board only), and collaborative sticky notes in topic state.

## Interactive React demo (Sticky Notes Room)

1. Start Phoenix (same as below), e.g. `cd cachepuppy_core && mix phx.server`.
2. Build SDK packages once (the app links both via `file:` paths):

   ```bash
   (cd sdk/javascript && npm ci && npm run build) && (cd sdk/react && npm ci && npm run build)
   ```

3. Run the UI:

   ```bash
   cd example/javascript_demo/interactive && npm ci && npm run dev
   ```

4. Open the printed local URL (usually `http://localhost:5173`). Enter a name and colour, connect, then move the pointer over the **sticky notes board** to publish `cursor_tracked` events; posting a note calls `setTopicState` with a `notes` list. Open a second browser window to see ghost cursors on the board and shared notes.

Optional: copy `.env.example` to `.env` and set `VITE_WS_URL` if your websocket endpoint differs from `ws://127.0.0.1:4000/socket/websocket`.

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

**3) Build SDK packages + run interactive demo**

From repo root:

```bash
(cd sdk/javascript && npm ci && npm run build) && (cd sdk/react && npm ci && npm run build) && (cd example/javascript_demo/interactive && npm ci && npm run dev)
```

Environment overrides (optional):

- `VITE_WS_URL` — WebSocket URL used by the interactive app (default `ws://127.0.0.1:4000/socket/websocket`)
- `PORT` — Webhook server listen port when using `webhook-server` (default `8765`)
