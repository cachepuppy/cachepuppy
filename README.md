<div align="center">

<img src="assets/logo.png" alt="CachePuppy" width="96" />

# CachePuppy

**The open-source infrastructure layer you didn't know you were missing.**

Realtime WebSockets · Distributed Caching · Workflow Orchestration — all in one deployable, scalable Elixir beast.

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](LICENSE)
[![Built with Elixir](https://img.shields.io/badge/Built%20with-Elixir-6e4a7e.svg)](https://elixir-lang.org/)
[![Powered by Phoenix](https://img.shields.io/badge/Powered%20by-Phoenix-orange.svg)](https://www.phoenixframework.org/)
[![Docs](https://img.shields.io/badge/Docs-docs.cachepuppy.com-green)](https://docs.cachepuppy.com)

[Website](https://cachepuppy.com) · [Documentation](https://docs.cachepuppy.com) · [SDKs](#sdks) · [Self-host](#self-hosting)

</div>

---

## What is CachePuppy?

Most apps end up duct-taping together Redis, a WebSocket server, a job queue, and a workflow engine — each with its own ops burden, failure modes, and billing.

**CachePuppy replaces all of that.**

It's an open-source, self-hostable infrastructure layer built on Elixir and Phoenix that gives you:

- ⚡ **Realtime, stateful WebSockets** — pub/sub with per-topic state and webhook sync
- 🗄️ **Distributed ETS-backed key-value store** — Redis-like, sharded, durable, and fast
- 🔄 **Workflow orchestration** — AI workflows, state machines, durable execution

The black box is fully open. Deploy it on as many nodes as you need — it scales horizontally out of the box.

---

## Features

### ⚡ Feature 1 — Realtime Scalable WebSockets

> Pub/sub infrastructure with stateful topics, built for production scale.

- **Publish & Subscribe to topics** via clean SDK APIs
- **Per-topic state** — each unique topic gets its own isolated process holding live state
- **Phoenix PubSub** handles the broadcast layer; topic processes handle state independently
- **Webhook flush** — sync topic state to your database on-demand or on a schedule, with configurable retry policies and timers
- **Horizontal scale** — WebSocket and topic processes are distributed across your node cluster

**Use it for:** live dashboards, multiplayer features, collaborative tools, presence, notifications, data sync pipelines.

```js
// Subscribe to a topic
await cachepuppy.subscribe("room:42", (state) => {
  console.log("New state:", state);
});

// Publish a state update
await cachepuppy.publish("room:42", { users: 12, lastMessage: "hey" });

// Flush topic state to your DB via webhook
await cachepuppy.flush("room:42");
```

---

### 🗄️ Feature 2 — Distributed Redis-like ETS Cache

> A Redis replacement that lives inside your Elixir cluster — with sharding, durability, and parallelism baked in.

- **Sharded & distributed** — tables are split across nodes; shards are managed by [Horde](https://github.com/derekkraan/horde) so they survive node failure and rebalance automatically
- **Durable shard processes** — each shard maintains its own WAL (Write-Ahead Log) and snapshots for crash recovery
- **Consistent writes via process queuing** — `SET` operations are serialized through the shard process, no race conditions
- **Parallel reads via ETS** — `GET` operations bypass the process entirely and read directly from the node's ETS table for maximum throughput
- **TTL support** — set expiry on any key; hot key optimizations built in
- **Full key lifecycle** — `SET`, `GET`, `DELETE` all exposed via API
- **Smart routing** — key + table are hashed to determine the shard ID, then the owning node is resolved via Horde's registry

```bash
# Via HTTP API
POST /cache/set   { "table": "sessions", "key": "user:99", "value": "...", "ttl": 3600 }
GET  /cache/get?table=sessions&key=user:99
DELETE /cache/delete?table=sessions&key=user:99
```

---

### 🔄 Feature 3 — Workflow Orchestration

> Durable, stateful execution for AI pipelines and business workflows — without changing how you write code.

- **AI Workflows** — chain LLM calls, tool use, and side effects with guaranteed execution
- **State Machines** — model complex business logic as explicit states and transitions
- **Durable state** — workflow state survives crashes, restarts, and deploys
- **Zero framework lock-in** — write your logic as plain API endpoints; CachePuppy handles the orchestration around them

Think Temporal or Trigger.dev, but open-source and co-located with your cache and WebSocket layer.

```js
// Define a workflow
cachepuppy.workflow("onboard-user", [
  { step: "create-account", endpoint: "/api/users/create" },
  { step: "send-welcome", endpoint: "/api/emails/welcome" },
  { step: "provision-trial", endpoint: "/api/billing/trial" },
]);

// Trigger it — CachePuppy handles retries, state, and failures
await cachepuppy.trigger("onboard-user", { email: "user@example.com" });
```

---

## Why Elixir?

CachePuppy is built on Elixir and Phoenix — not by accident.

- **Processes are cheap.** Millions of topic and shard processes can run concurrently without breaking a sweat.
- **OTP gives you durability for free.** Supervision trees, crash recovery, and process isolation are core primitives — not bolt-ons.
- **Horde makes distribution trivial.** Shard processes are automatically redistributed when nodes join or leave the cluster.
- **Phoenix PubSub is battle-tested.** The same pub/sub powering millions of LiveView connections powers your topics.

You deploy nodes. CachePuppy does the rest.

---

## SDKs

CachePuppy ships with SDKs for all major languages. The server is the open-source black box — the SDKs are just thin clients.

| Language                | Install                               |
| ----------------------- | ------------------------------------- |
| JavaScript / TypeScript | `npm install cachepuppy`              |
| Python                  | `pip install cachepuppy`              |
| Go                      | `go get github.com/cachepuppy/go-sdk` |
| Ruby                    | `gem install cachepuppy`              |
| Elixir                  | `{:cachepuppy, "~> 1.0"}`             |

---

## Self-hosting

CachePuppy is fully open-source. Run it anywhere.

```bash
# Clone the repo
git clone https://github.com/cachepuppy/cachepuppy
cd cachepuppy

# Configure
cp config/example.env .env
# edit .env with your settings

# Run with Docker
docker compose up

# Or deploy to a cluster
docker compose -f docker-compose.cluster.yml up --scale cachepuppy=3
```

See the [self-hosting guide](https://docs.cachepuppy.com/self-hosting) for production configuration, clustering, persistent storage, and load balancing.

---

## Architecture Overview
