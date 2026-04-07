# beamline_demo_app

Frontend-only demo for validating Beamline SDK usage against the managed Elixir websocket server.

## Purpose

- Exercise SDK lifecycle events.
- Exercise publish/subscribe message flow.

## Structure

- `frontend`: Browser-style client simulation using `beamline_js_sdk`.

## Scenario

1. Frontend connects to websocket endpoint.
2. Frontend subscribes to `demo.events`.
3. Frontend publishes `demo.events:client_ready`.
4. Frontend logs incoming events from the server.
