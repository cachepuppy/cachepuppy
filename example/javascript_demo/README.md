# javascript_demo

Frontend-only demo for validating CachePuppy SDK usage against the managed Elixir websocket server.

## Purpose

- Exercise SDK lifecycle events.
- Exercise publish/subscribe message flow.
- Exercise per-topic shared state flow (`setTopicState`, `getTopicState`, `clearTopicState`, `state_updated`).
- Validate single cluster owner topic behavior across load-balanced backend nodes.

## Structure

- `frontend`: Browser-style client simulation using the `cachepuppy-js-sdk` package (`file:` link to `sdk/javascript`).

## Scenario

1. Frontend connects to websocket endpoint.
2. Frontend subscribes to `demo.events`.
3. Frontend publishes `demo.events:client_ready`.
4. Frontend updates and reads shared topic state.
5. Frontend calls `clearTopicState` on the same topic and demonstrates that read-after-clear returns an error.
6. Frontend logs incoming events from the server.

# Demo Frontend Contract

`frontend` runs a small Node script that uses `cachepuppy-js-sdk` against a live Phoenix server (`transport: "phoenix"`).

## Scenario

1. Optional HTTP probes call `GET /api/health` through the load balancer (expect mixed `node` values when multiple backends are behind nginx).
2. Five clients connect via **the same WS URL** (typically `ws://127.0.0.1:4000/socket/websocket` when using Docker Compose + nginx) and subscribe to topic `demo_room`. Live presence is logged for all five.
3. `eve` calls `unsubscribe(demo_room)` — leaves the topic (Phoenix channel leave); the room stays open for the other four. Presence on the remaining clients should move to four members.
4. `alice` calls `publish` — only the four remaining members should log `room_broadcast` (`eve` must not).
5. `alice` calls `publishTo` with `["carol"]` — only `carol` should log `direct_to_one`.
6. `alice` calls `setTopicState` on `demo_room` — all subscribers still in the room should log `state_updated`.
7. `bob` calls `getTopicStateWithMeta` — returns the shared topic state map plus node metadata.
8. `alice` reports `clientCount` for `demo_room` (expect four), then calls `clearTopicState` on `demo_room` — server-side topic process shutdown. `bob` calling `getTopicState` afterward should fail with `topic_not_found`.
9. All clients `disconnect`.

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
