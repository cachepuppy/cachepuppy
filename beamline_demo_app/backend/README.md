# Demo Backend Contract

`backend` simulates a service process that consumes `beamline_js_sdk`.

## Responsibilities

- Connect to mock transport and emit lifecycle logs.
- Subscribe to `demo.events`.
- Emit follow-up publish events.

## Expected behavior

- On `demo.events:ping`, publish `demo.events:pong`.
- On connection changes, print state transitions.
