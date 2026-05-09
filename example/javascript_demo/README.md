# javascript_demo

Interactive React demo for validating CachePuppy SDK usage against the managed Elixir websocket server.

## Purpose

- Exercise SDK lifecycle events.
- Exercise publish/subscribe message flow.
- Exercise per-topic shared state flow (`setTopicState`, `configureTopicWebhook`, `getTopicState`, `clearTopicState`, `state_updated`).
- Validate single cluster owner topic behavior across load-balanced backend nodes.

## Structure

- `webhook-server`: Minimal Node server that logs `POST /topic-state` JSON bodies (run this when demoing server-side webhook flush).
- `interactive`: Vite + React browser app — uses `@cachepuppy/react` (backed by `@cachepuppy/core`) to join `sticky_notes_room`, share ephemeral `cursor_tracked` publishes (notes board only), and collaborative sticky notes in topic state.
- `workflows/server`: Express server that mirrors the five e2e workflow scenarios (serial, static parallel + merge, dynamic parallel + merge, parallel + summary merge, nested parallel fan-out) under `/scenario1` … `/scenario5`.
- `workflows/web`: Vite + React UI to start each scenario and show live step status from `graph_diff` websocket events on `workflow:<id>`.

## Workflows demo (orchestration + realtime graph)

This showcase matches the Elixir e2e developer servers: each **`POST /scenarioN/start`** body is `{ "paragraph": string }`; CachePuppy calls back into the demo server using **`WORKFLOW_DEMO_PUBLIC_URL`** (must be reachable from the Phoenix node that runs step HTTP).

1. Start Phoenix, e.g. `cd cachepuppy_core && mix phx.server` (default API `http://127.0.0.1:4000`).
2. Build SDKs once:

   ```bash
   (cd sdk/javascript && npm ci && npm run build) && (cd sdk/react && npm ci && npm run build)
   ```

3. Start the workflows demo server (default `http://127.0.0.1:8787`):

   ```bash
   cd example/javascript_demo/workflows/server && npm ci && npm start
   ```

   Configure via environment (see `workflows/server/.env.example`):

   - `PORT` — listen port (default `8787`)
   - `CACHEPUPPY_API_BASE` — CachePuppy HTTP origin (default `http://127.0.0.1:4000`)
   - `WORKFLOW_DEMO_PUBLIC_URL` — public URL of this Node server for workflow step callbacks (default `http://127.0.0.1:8787`). If Phoenix runs in Docker, use a host-reachable URL (for example `http://host.docker.internal:8787` on Docker Desktop).

4. Start the web UI:

   ```bash
   cd example/javascript_demo/workflows/web && npm ci && npm run dev
   ```

5. Open the printed dev URL (for example `http://localhost:5173`). Optionally copy `workflows/web/.env.example` to `.env` and set `VITE_WS_URL` and `VITE_WORKFLOW_DEMO_API`.

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
