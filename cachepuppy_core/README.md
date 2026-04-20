# cachepuppy_core

`cachepuppy_core` is the Phoenix websocket backend for CachePuppy.

This version is intentionally auth-free and focused on core realtime behavior.

## Local run

- `mix setup`
- `mix phx.server`

With `mix phx.server`, the app runs on `http://localhost:4000`. With Docker Compose + nginx, use `http://127.0.0.1:4000` as the single entry point to the cluster.

## HTTP endpoint

- `GET /healthz` is liveness-only and returns `200` when the node process is up.
- `GET /readyz` is quorum-aware readiness and returns `200` only when cluster quorum is met.
- `GET /api/health` returns status plus cluster visibility (`node`, `cluster_size`, `connected_nodes`).

## Server HTTP API (prototype)

JSON routes for backends that should not open a websocket per request. **There is no authentication on these routes** (same trust model as `/api/cache/*` and the open `/socket` connect). Do not expose them on the public internet without a reverse proxy, network isolation, or future service auth.

Base path: **`/api/server/v1`**. The `:topic` path segment is the **logical** room name (without the `events:` prefix used on the websocket).

| Method | Path | Purpose |
|--------|------|---------|
| `PUT` | `/topics/:topic/state` | Replace shared topic state. Request body is the state JSON object (same map as websocket `set_state` inner `payload`). Response: `%{"state" => map}`. When the stored map changes, subscribers receive the same `state_updated` envelope as over the channel. |
| `GET` | `/topics/:topic/state` | Read current topic state. Response: `%{"state" => map, "meta" => %{...}}` (same shape as websocket `get_state` reply). `404` with `reason` `topic_not_found` if no topic process exists. |
| `DELETE` | `/topics/:topic` | Stop the topic process (`close_topic`). Response: `%{"closed" => true}` or `%{"closed" => false}` if there was nothing to stop. |
| `POST` | `/topics/:topic/messages` | Fan out a publish to websocket subscribers. JSON body: `%{"event" => string, "payload" => any}`. Response: `202` and `%{"ok" => true}`. Envelope matches channel publishes; `meta.clientId` is `server_api`. |
| `GET` | `/topics/:topic/presence` | Presence snapshot for the room. Response: `%{"client_count" => integer, "presence" => map}` (same underlying Presence topic as `events:<topic>` joins). |

These handlers reuse [`TopicManager`](lib/cachepuppy_core/topic_manager.ex) and the same PubSub topic as [`EventChannel`](lib/cachepuppy_core_web/channels/event_channel.ex), via [`TopicRoom`](lib/cachepuppy_core_web/topic_room.ex), so behavior stays aligned with the browser websocket contract.

Required runtime env for quorum:

- `TOTAL_NODES` (required, positive integer)
- `QUORUM_POLL_INTERVAL_MS` (optional, default `2000`)
- `QUORUM_GRACE_MS` (optional, default `20000`)

Quorum behavior:

- If quorum is lost, the node immediately blocks snapshot/checkpoint finalization and enters a grace period.
- WAL appends continue during grace.
- If quorum is not restored before grace expires, the node hard-stops.

## Websocket endpoint

- Socket path: `/socket/websocket`
- Channel topic formats:
  - `events:<topic_name>` — shared room messaging and topic state
  - `session` — private per-connection state (join once per socket; no room name)
- Optional connect param: `client_id` for custom client identity labels.

Supported inbound events on **`events:<topic_name>`**:

- `"publish"` with payload `%{"event" => "...", "payload" => ...}`
- `"message"` envelope with `%{"type" => "publish", "event" => "...", "payload" => ...}`
- `"client_count"` returns `%{"client_count" => integer}` for the current topic (Presence member count).
- `"set_state"` with payload `%{"payload" => map}` updates topic shared state. If the map equals the stored state, the reply is still `ok` but no `state_updated` broadcast is sent.
- `"configure_topic_webhook"` with `%{"flush" => true, "url" => "http(s)://...", "frequency" => seconds}` enables a repeating timer on the topic process: each tick POSTs JSON `%{"topic", "state", "ts"}` to `url` when state has changed since the last post. `%{"flush" => false}` disables webhooks and clears the timer.
- `"get_state"` returns `%{"state" => map}` for the current topic process state.
- `"close_topic"` explicitly terminates the per-topic process and returns `%{"closed" => boolean}`.

Supported inbound events on **`session`**:

- `"set_session_state"` with payload `%{"payload" => map}` stores private state for this websocket connection only.
- `"get_session_state"` returns `%{"state" => map}` for that connection.
- `"set_cache_data"` with payload `%{"table" => string, "key" => string, "value" => any, "ttl_ms" => pos_integer?}` writes through the same cache pipeline as `/api/cache/setdata`.
- `"get_cache_data"` with payload `%{"table" => string, "key" => string}` reads through the same cache pipeline as `/api/cache/getdata`.
- `"delete_cache_data"` with payload `%{"table" => string, "key" => string}` deletes through the same cache pipeline as `/api/cache/deletedata`.
- Cache replies mirror HTTP JSON bodies:
  - set/get: `%{"table" => table, "key" => key, "value" => value}`
  - delete: `%{"table" => table, "key" => key, "deleted" => boolean}`
- Cache errors reuse the same reasons as HTTP where applicable (`invalid_payload`, `invalid_table_or_key`, `invalid_ttl_ms`, `rehydrating`, `rpc_failed`, `shard_unavailable`).

Broadcast behavior:

- Server broadcasts `"message"` events to all subscribers on the channel topic.
- Outbound message shape follows the CachePuppy envelope fields (`v`, `type`, `topic`, `event`, `payload`, `ts`, `meta`).
- Topic state updates are broadcast as a normal `"message"` with `event: "state_updated"` and the full current topic state in `payload`.

## Per-topic state process

Each `events:<topic_name>` topic has a single cluster owner process (one process for the topic across connected nodes) that owns shared in-memory state.

- The topic process is started on first join and registered cluster-wide.
- `set_state` replaces the current topic state when the payload differs; then broadcasts `state_updated`. Identical payloads are idempotent (no broadcast).
- Optional `configure_topic_webhook` stores webhook URL and tick interval; a dirty flag is set on real state changes and cleared after a successful tick posts (or when there was nothing to send).
- `get_state` returns the latest full state map regardless of which backend node handles the request.
- `close_topic` manually stops the global topic owner process.
- Idle fallback: if the topic process is inactive, it is stopped after `:topic_idle_timeout_ms` (default `120_000`).
- If the owner node fails, the topic can be recreated on another node with empty state.

## Private session channel

Join Phoenix topic `session` (fixed string) for connection-scoped state that does not use a room name.

- One channel process per joined socket; state is not shared with other clients.
- `set_session_state` / `get_session_state` behave like topic state but only for that connection.
- State is dropped when the socket disconnects or the `session` channel is left.

### Event payload examples

- `set_state` push:
  - `%{"payload" => %{"count" => 1, "status" => "ready"}}`
- `set_state` reply:
  - `%{"state" => %{"count" => 1, "status" => "ready"}}`
- `state_updated` broadcast (`"message"` event payload):
  - `%{"v" => 1, "type" => "publish", "topic" => "my_topic", "event" => "state_updated", "payload" => %{"count" => 1, "status" => "ready"}, "ts" => 1_712_345_678_901, "meta" => %{"clientId" => "topic_process"}}`
- `get_state` reply:
  - `%{"state" => %{"count" => 1, "status" => "ready"}}`
- `set_session_state` push:
  - `%{"payload" => %{"draft" => "hello"}}`
- `set_session_state` reply:
  - `%{"state" => %{"draft" => "hello"}}`
- `get_session_state` reply:
  - `%{"state" => %{"draft" => "hello"}}`
- `set_cache_data` push:
  - `%{"table" => "users", "key" => "user_1", "value" => %{"role" => "admin"}, "ttl_ms" => 30_000}`
- `set_cache_data` reply:
  - `%{"table" => "users", "key" => "user_1", "value" => %{"role" => "admin"}}`
- `get_cache_data` push:
  - `%{"table" => "users", "key" => "user_1"}`
- `get_cache_data` reply:
  - `%{"table" => "users", "key" => "user_1", "value" => %{"role" => "admin"}}`
- `delete_cache_data` push:
  - `%{"table" => "users", "key" => "user_1"}`
- `delete_cache_data` reply:
  - `%{"table" => "users", "key" => "user_1", "deleted" => true}`
- `close_topic` reply:
  - `%{"closed" => true}`

## Local libcluster multi-node testing

This project supports local 3-node clustering via `libcluster` and Docker Compose. An **nginx** service load-balances HTTP and WebSockets across `app1`, `app2`, and `app3` on **port 4000** (non-sticky round-robin).

### Start cluster

- `docker compose up --build -d`
- `docker compose ps`

`nginx` waits until all three Phoenix replicas pass their HTTP healthchecks before starting, so Docker DNS can resolve `app1`–`app3` and nginx does not fail with `host not found in upstream`.

`app1`–`app3` share the same image tag (`cachepuppy_core_app:latest`) so one `docker compose build` / `up --build` updates every replica (healthchecks use quorum-aware `/readyz`).

Check node visibility:

- **Through the load balancer** (single URL; repeated calls may hit different backends):
  - `curl -s http://127.0.0.1:4000/api/health`
  - Run several times or: `for i in 1 2 3 4 5 6; do curl -s http://127.0.0.1:4000/api/health | jq -r .node; done`
- **Direct to each BEAM node** (optional, ports published for debugging and churn tests):
  - `curl http://localhost:4001/api/health`
  - `curl http://localhost:4002/api/health`
  - `curl http://localhost:4003/api/health`

Expected steady-state: each response reports `cluster_size: 3`. Via nginx, `node` may vary per request.

### Interactive demo (React, behind LB)

From the repository root, with the stack running (build the SDK packages first if you have not already):

```bash
(cd sdk/javascript && npm ci && npm run build) && (cd sdk/react && npm ci && npm run build) && (cd example/javascript_demo/interactive && npm ci && npm run dev)
```

The interactive demo uses `ws://localhost:4000/socket/websocket` by default (nginx via `VITE_WS_URL` override) and exercises publish/presence/topic-state interactions between multiple browser windows.

### Churn test workflow

1. **Single node stop/start**
   - `docker compose stop app2`
   - Verify `cluster_size: 2` from `app1` or `app3`
   - `docker compose start app2`
   - Verify all nodes return to `cluster_size: 3`
2. **Abrupt kill/restart**
   - `docker compose kill app3`
   - Verify remaining nodes converge to `cluster_size: 2`
   - `docker compose start app3`
   - Verify convergence to `cluster_size: 3`
3. **Rolling restarts**
   - `docker compose restart app1`
   - `docker compose restart app2`
   - `docker compose restart app3`
   - Verify cluster returns to `cluster_size: 3`
4. **Short partition/heal (optional)**
   - `docker network disconnect cachepuppy_core_default cachepuppy_core-app2-1`
   - Verify app2 is removed from peers
   - `docker network connect cachepuppy_core_default cachepuppy_core-app2-1`
   - Verify app2 rejoins and cluster returns to 3

### Tear down

- `docker compose down`
