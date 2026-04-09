# Demo Frontend Contract

`frontend` runs a small Node script that uses `cachepuppy_js_sdk` against a live Phoenix server (`transport: "phoenix"`).

## Scenario

1. Optional HTTP probes call `GET /api/health` through the load balancer (expect mixed `node` values when multiple backends are behind nginx).
2. Five clients (`alice`, `bob`, `carol`, `dave`, `eve`) connect via **the same WS URL** (typically `ws://127.0.0.1:4000/socket/websocket` when using Docker Compose + nginx) and subscribe to topic `demo_room`.
3. `alice` calls `publish` — all five should log `room_broadcast`.
4. `alice` calls `publishTo` with `["carol"]` — only `carol` should log `direct_to_one`.

## Run

**Multi-node cluster + nginx (recommended for LB validation)**

1. `cd cachepuppy_core && docker compose up --build -d`
2. From repo root: `npm run demo:frontend`

**Single local Phoenix (no Docker)**

1. `cd cachepuppy_core && mix phx.server`
2. From repo root: `npm run demo:frontend`

Environment overrides (optional):

- `API_BASE` — HTTP origin for health probes (default `http://127.0.0.1:4000`)
- `WS_URL` — WebSocket URL (default `ws://127.0.0.1:4000/socket/websocket`)
