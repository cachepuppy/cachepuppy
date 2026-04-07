# beamline_demo_app

Demo application for validating Beamline SDK usage before the Elixir backend is implemented.

## Purpose

- Exercise SDK lifecycle events.
- Exercise publish/subscribe message flow.
- Exercise request/response with timeout behavior.

## Structure

- `backend`: Node.js process using `beamline_js_sdk`.
- `frontend`: Browser-style client simulation using `beamline_js_sdk`.

## Scenario

1. Backend connects and subscribes to `demo.events`.
2. Frontend connects and subscribes to `demo.events`.
3. Frontend publishes `demo.events:ping`.
4. Backend receives and publishes `demo.events:pong`.
5. Frontend sends a `request` (`demo.rpc:get_status`) and backend responds.

Both sides use SDK mock transport in this phase.
