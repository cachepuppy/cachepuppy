# Demo Frontend Contract

`frontend` simulates a browser-side app consuming `beamline_js_sdk`.

## Responsibilities

- Connect to mock transport and emit lifecycle logs.
- Subscribe to `demo.events`.
- Publish `demo.events:ping`.
- Issue `request` to `demo.rpc:get_status`.
- Listen for protocol events.

## Expected behavior

- Receives `demo.events:pong` after ping.
- Receives valid request response payload for `get_status`.

Note: the current `frontend/src/main.ts` starts an embedded mock backend client in-process because mock transport is in-memory and process-local.
