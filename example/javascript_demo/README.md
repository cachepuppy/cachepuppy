# javascript_demo

Frontend-only demo for validating CachePuppy SDK usage against the managed Elixir websocket server.

## Purpose

- Exercise SDK lifecycle events.
- Exercise publish/subscribe message flow.
- Exercise per-topic shared state flow (`setTopicState`, `getTopicState`, `closeTopic`, `state_updated`).
- Validate single cluster owner topic behavior across load-balanced backend nodes.

## Structure

- `frontend`: Browser-style client simulation using the `cachepuppy-js-sdk` package (`file:` link to `sdk/javascript`).

## Scenario

1. Frontend connects to websocket endpoint.
2. Frontend subscribes to `demo.events`.
3. Frontend publishes `demo.events:client_ready`.
4. Frontend updates and reads shared topic state.
5. Frontend closes the topic process and demonstrates that read-after-close returns an error.
6. Frontend logs incoming events from the server.

# Demo Frontend Contract

`frontend` runs a small Node script that uses `cachepuppy-js-sdk` against a live Phoenix server (`transport: "phoenix"`).

## Scenario

1. Optional HTTP probes call `GET /api/health` through the load balancer (expect mixed `node` values when multiple backends are behind nginx).
2. Five clients (`alice`, `bob`, `carol`, `dave`, `eve`) connect via **the same WS URL** (typically `ws://127.0.0.1:4000/socket/websocket` when using Docker Compose + nginx) and subscribe to topic `demo_room`.
3. `alice` calls `publish` — all five should log `room_broadcast`.
4. `alice` calls `publishTo` with `["carol"]` — only `carol` should log `direct_to_one`.
5. `alice` calls `setTopicState` — all subscribers should log `state_updated` with the same full state payload, even when clients are routed to different backend nodes.
6. `bob` calls `getTopicState` — returns the same shared topic state map regardless of which backend node handled the call.
7. `alice` calls `closeTopic` — explicit topic process shutdown.
8. `bob` calls `getTopicState` again — returns an error (`topic_not_found`) and does not recreate the topic process.

## Run

**Multi-node cluster + nginx (recommended for LB validation)**

1. `cd cachepuppy_core && docker compose up --build -d`
2. From repo root: `(cd sdk/javascript && npm ci && npm run build) && (cd example/javascript_demo/frontend && npm ci && npm run build && npm start)`

**Single local Phoenix (no Docker)**

1. `cd cachepuppy_core && mix phx.server`
2. From repo root: `(cd sdk/javascript && npm ci && npm run build) && (cd example/javascript_demo/frontend && npm ci && npm run build && npm start)`

Environment overrides (optional):

- `API_BASE` — HTTP origin for health probes (default `http://127.0.0.1:4000`)
- `WS_URL` — WebSocket URL (default `ws://127.0.0.1:4000/socket/websocket`)
