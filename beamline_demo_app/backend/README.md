# Demo Backend Contract

`backend` simulates a service process that consumes `beamline_js_sdk`.

## Responsibilities

- Connect to mock transport and emit lifecycle logs.
- Subscribe to `demo.events`.
- Handle frontend request actions under `demo.rpc`.
- Emit responses and follow-up publish events.

## Expected behavior

- On `demo.events:ping`, publish `demo.events:pong`.
- On `request` with action `get_status`, return service metadata.
- On connection changes, print state transitions.
