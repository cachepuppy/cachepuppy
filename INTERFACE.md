# Beamline Calls (Simple View)

This page is a plain-English list of calls available to apps that talk to the Beamline core Elixir server over websockets.

## 1) Start a client

`createClient(...)`

Creates a Beamline client object.

## 2) Open and close connection

- `connect()` - open websocket connection to Beamline server.
- `disconnect()` - close websocket connection.
- `getState()` - check connection state (`connected`, `disconnected`, etc.).
- `destroy()` - fully stop and clean up the client.

## 3) Topic-based messaging (publish/subscribe)

- `subscribe(topic, handler)` - start listening to a topic.
- `unsubscribe(topic)` - stop listening to a topic.
- `publish(topic, event, payload)` - send an event to everyone subscribed to that topic.

Example: publish `event = "order_created"` to topic `orders`.

## 4) Request/response calls

- `request(topic, action, payload)` - ask Beamline server to do something and wait for reply.
- `respond(correlationId, ok, payload, error)` - send a reply to a request.

Use this when you need a direct answer (not just a broadcast event).

## 5) Connection and message events you can listen to

- `on("connected", handler)` - called when connection opens.
- `on("disconnected", handler)` - called when connection closes.
- `on("reconnecting", handler)` - called when client is retrying.
- `on("stateChange", handler)` - called whenever connection state changes.
- `on("message", handler)` - called for normal protocol messages.
- `on("error", handler)` - called on errors.

## What this means for non-technical teams

Beamline gives you 2 simple communication styles:

1. Broadcast events by topic (`publish/subscribe`)
2. Direct ask-and-reply (`request/response`)
