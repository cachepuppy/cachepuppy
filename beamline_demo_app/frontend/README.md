# Demo Frontend Contract

`frontend` simulates a browser-side app consuming `beamline_js_sdk`.

## Responsibilities

- Connect to mock transport and emit lifecycle logs.
- Subscribe to `demo.events`.
- Publish `demo.events:client_ready`.
- Listen for protocol events.

## Expected behavior

- Logs incoming events for `demo.events`.

For production usage, point the SDK `url` to the hosted Beamline Elixir websocket endpoint.
