# cachepuppy_core

`cachepuppy_core` is the Phoenix websocket backend for CachePuppy.

This version is intentionally auth-free and focused on core realtime behavior.

## Local run

- `mix setup`
- `mix phx.server`

With `mix phx.server`, the app runs on `http://localhost:4000`. With Docker Compose + nginx, use `http://127.0.0.1:4000` as the single entry point to the cluster.

## HTTP endpoint

- `GET /api/health` returns status plus cluster visibility (`node`, `cluster_size`, `connected_nodes`).

## Websocket endpoint

- Socket path: `/socket/websocket`
- Channel topic formats:
  - `events:<topic_name>` — shared room messaging and topic state
  - `session` — private per-connection state (join once per socket; no room name)
- Optional connect param: `client_id` for custom client identity labels.

Supported inbound events on **`events:<topic_name>`**:

- `"publish"` with payload `%{"event" => "...", "payload" => ...}`
- `"publish_to"` with payload `%{"event" => "...", "payload" => ..., "client_ids" => [...]}` (only those Presence keys receive the outbound `message`)
- `"message"` envelope with `%{"type" => "publish", "event" => "...", "payload" => ...}`
- `"client_count"` returns `%{"client_count" => integer}` for the current topic (Presence member count).
- `"set_state"` with payload `%{"payload" => map}` updates topic shared state and broadcasts a `state_updated` message event.
- `"get_state"` returns `%{"state" => map}` for the current topic process state.
- `"close_topic"` explicitly terminates the per-topic process and returns `%{"closed" => boolean}`.

Supported inbound events on **`session`**:

- `"set_session_state"` with payload `%{"payload" => map}` stores private state for this websocket connection only.
- `"get_session_state"` returns `%{"state" => map}` for that connection.

Broadcast behavior:

- Server broadcasts `"message"` events to all subscribers on the channel topic.
- Outbound message shape follows the CachePuppy envelope fields (`v`, `type`, `topic`, `event`, `payload`, `ts`, `meta`).
- Topic state updates are broadcast as a normal `"message"` with `event: "state_updated"` and the full current topic state in `payload`.

## Per-topic state process

Each `events:<topic_name>` topic has a single cluster owner process (one process for the topic across connected nodes) that owns shared in-memory state.

- The topic process is started on first join and registered cluster-wide.
- `set_state` replaces the current topic state with the provided map and then broadcasts `state_updated`.
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
- `close_topic` reply:
  - `%{"closed" => true}`

## Local libcluster multi-node testing

This project supports local 3-node clustering via `libcluster` and Docker Compose. An **nginx** service load-balances HTTP and WebSockets across `app1`, `app2`, and `app3` on **port 4000** (non-sticky round-robin).

### Start cluster

- `docker compose up --build -d`
- `docker compose ps`

`nginx` waits until all three Phoenix replicas pass their HTTP healthchecks before starting, so Docker DNS can resolve `app1`–`app3` and nginx does not fail with `host not found in upstream`.

`app1`–`app3` share the same image tag (`cachepuppy_core_app:latest`) so one `docker compose build` / `up --build` updates every replica (healthchecks use `curl` from the runtime image).

Check node visibility:

- **Through the load balancer** (single URL; repeated calls may hit different backends):
  - `curl -s http://127.0.0.1:4000/api/health`
  - Run several times or: `for i in 1 2 3 4 5 6; do curl -s http://127.0.0.1:4000/api/health | jq -r .node; done`
- **Direct to each BEAM node** (optional, ports published for debugging and churn tests):
  - `curl http://localhost:4001/api/health`
  - `curl http://localhost:4002/api/health`
  - `curl http://localhost:4003/api/health`

Expected steady-state: each response reports `cluster_size: 3`. Via nginx, `node` may vary per request.

### Demo frontend (multi-client, behind LB)

From the repository root, with the stack running (build the JS SDK first if you have not already):

```bash
(cd sdk/javascript && npm ci && npm run build) && (cd example/javascript_demo/frontend && npm ci && npm run build && npm start)
```

The demo uses `http://localhost:4000` and `ws://localhost:4000` by default (nginx). It runs HTTP probes first (to show LB distribution), then opens five WebSocket clients and runs the same publish / `publishTo` checks as before.

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
