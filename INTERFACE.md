# Beamline Calls (Simple View)

This page is a plain-English list of calls available to apps that talk to the Beamline core Elixir server over websockets.

## 1) Start a client

`createClient(...)`

Creates a Beamline client object.

Optional: pass `clientId` to label this connection with your own custom ID.

## 2) Open and close connection

- `connect()` - open websocket connection to Beamline server.
- `disconnect()` - close websocket connection.
- `getState()` - check connection state (`connected`, `disconnected`, etc.).
- `destroy()` - fully stop and clean up the client.

## 3) Topic-based messaging (publish/subscribe)

- `subscribe(topic, handler)` - start listening to a topic.
- `unsubscribe(topic)` - stop listening to a topic.
- `publish(topic, event, payload)` - send an event to everyone subscribed to that topic.
- `publishTo(topic, event, payload, clientIds)` - send an event only to the listed client IDs that are in that topic.
- `clientCount(topic)` - get how many clients are connected in that topic.

Example: publish `event = "order_created"` to topic `orders`.

## 3b) Session state (this connection only, no room topic)

Private cache for **this** websocket only (other clients never see it). The SDK joins a fixed server channel named `session` for you when you first call these:

- `setSessionState(payload)` - replace session state for this connection.
- `getSessionState()` - read current session state.

Session state is cleared when this client disconnects or reconnects. You do **not** need to `subscribe` to a room topic to use session state.

## 3c) Shared topic state (room-scoped)

- `setTopicState(topic, payload)` — replace shared state for the topic. Subscribers get `state_updated` only when the new payload is different from what is already stored (idempotent repeats are quiet).
- `configureTopicWebhook(topic, { flush, url?, frequency? })` — separately enable or disable periodic webhook delivery: when `flush` is true, the server POSTs `{ topic, state, ts }` to `url` on a timer; if the state changed since the last successful check, it sends and clears an internal dirty flag. `frequency` is the tick interval in seconds (default 10). When `flush` is false, webhook delivery is turned off. Client-supplied URLs are an SSRF risk in production; restrict or proxy in real deployments.
- `getTopicState(topic)` / metadata variant — read shared state.
- `clearTopicState(topic)` — tear down the topic process on the server.

## 4) Connection and message events you can listen to

- `on("connected", handler)` - called when connection opens.
- `on("disconnected", handler)` - called when connection closes.
- `on("reconnecting", handler)` - called when client is retrying.
- `on("stateChange", handler)` - called whenever connection state changes.
- `on("message", handler)` - called for normal protocol messages.
- `on("error", handler)` - called on errors.

## What this means for non-technical teams

Beamline gives you one simple communication style:

1. Broadcast events by topic (`publish/subscribe`)
