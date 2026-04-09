# cachepuppy_demo_app

Frontend-only demo for validating CachePuppy SDK usage against the managed Elixir websocket server.

## Purpose

- Exercise SDK lifecycle events.
- Exercise publish/subscribe message flow.
- Exercise per-topic shared state flow (`setTopicState`, `getTopicState`, `closeTopic`, `state_updated`).

## Structure

- `frontend`: Browser-style client simulation using `cachepuppy_js_sdk`.

## Scenario

1. Frontend connects to websocket endpoint.
2. Frontend subscribes to `demo.events`.
3. Frontend publishes `demo.events:client_ready`.
4. Frontend updates and reads shared topic state.
5. Frontend closes the topic process and demonstrates that read-after-close returns an error.
6. Frontend logs incoming events from the server.
