# @cachepuppy/core

TypeScript SDK that gives JavaScript developers access to CachePuppy websocket capabilities.

This package provides:

- Client lifecycle management
- Topic publish/subscribe
- Per-topic shared state helpers (`setTopicState`, `configureTopicWebhook`, `getTopicState`, `clearTopicState`)
- Per-connection private session state via the fixed `session` channel (`setSessionState`, `getSessionState`; no room topic)
- Per-connection cache helpers via the fixed `session` channel (`setData`, `getData`, `deleteData`)
- `onStateUpdated` helper for `state_updated` topic events
- Mock transport for local development and demo flows
- **Admin HTTP client** (`createAdminClient` / `CachePuppyAdminClient`) for server-side HTTP APIs without opening a websocket:
  - `/api/server/v1` topic APIs (`state`, `messages`, `presence`, `clear`)
  - `/api/cache/*` cache APIs (`setdata`, `getdata`, `deletedata`)

See `docs/api-design.md` for the API contract.

### Admin HTTP client

For backends that call CachePuppy’s **HTTP** topic routes (`PUT/GET …/state`, `POST …/messages`, `GET …/presence`, `DELETE …/topics/:topic`), use a separate admin client so those calls stay isolated from the websocket `CachePuppyClient`:

```ts
import { createAdminClient } from "@cachepuppy/core";

const admin = createAdminClient({
  url: "ws://localhost:4000/socket/websocket",
  // authToken: "...", // optional when the server enforces Bearer auth
});

await admin.setTopicState("my_room", { count: 1 });
const state = await admin.getTopicState("my_room");
await admin.sendTopicMessage("my_room", { event: "ping", payload: { from: "cron" } });
const { clientCount } = await admin.getTopicPresence("my_room");
await admin.setData("users", "alice", { role: "admin" }, { ttlMs: 30_000 });
const cached = await admin.getData("users", "alice");
const deleted = await admin.deleteData("users", "alice");
```

Server route details and prototype security notes: [`cachepuppy_core/README.md`](../../cachepuppy_core/README.md) (Server HTTP API section).

### Websocket cache calls on `CachePuppyClient`

When using the websocket client (`createClient`), cache operations are also available on the same client through the `session` channel:

```ts
const client = createClient({ url: "ws://localhost:4000/socket/websocket" });
await client.connect();

await client.setData("users", "alice", { role: "admin" }, { ttlMs: 30_000 });
const value = await client.getData("users", "alice");
const deleted = await client.deleteData("users", "alice");
```

Use whichever integration shape fits your app:
- websocket client (`CachePuppyClient`) for connection-oriented realtime flows
- admin HTTP client (`CachePuppyAdminClient`) for server-side HTTP workflows
