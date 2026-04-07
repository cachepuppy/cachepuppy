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
- `listClientIds(topic)` - get all currently connected client IDs in that topic.

Example: publish `event = "order_created"` to topic `orders`.

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
