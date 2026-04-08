# Demo Frontend Contract

`frontend` runs a small Node script that uses `beamline_js_sdk` against a live Phoenix server (`transport: "phoenix"`).

## Scenario

1. Three clients (`alice`, `bob`, `carol`) connect and subscribe to topic `demo_room`.
2. `alice` calls `publish` — all three should log `room_broadcast`.
3. `alice` calls `publishTo` with `["carol"]` — only `carol` should log `direct_to_one`.

## Run

1. Start Beamline core: `cd beamline_core && mix phx.server`
2. From repo root: `npm run demo:frontend`

Point `WS_URL` in `src/main.ts` at your deployed websocket if not local.
