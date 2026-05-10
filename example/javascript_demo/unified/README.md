# CachePuppy unified demo (Next.js)

A single Next.js app that demonstrates three CachePuppy capabilities under one
roof:

1. **Caching** – set / get / update / delete with TTL, called directly from the
   browser via `@cachepuppy/react`.
2. **Realtime** – live cursors of every participant in the room over Phoenix
   websockets.
3. **Workflows** – seven orchestration scenarios. The browser calls Next.js API
   routes (`/api/workflows/scenarioN/...`) which use `@cachepuppy/core`'s admin
   client to drive the workflow.

This replaces the previously separate `interactive`, `workflows/server` and
`workflows/web` projects with a single Next.js codebase.

## Prerequisites

- Node 18+ (Node 20 recommended).
- A running CachePuppy/Phoenix server reachable from this app at
  `ws://127.0.0.1:4000/socket/websocket` and `http://127.0.0.1:4000`.

## One-time setup

The two SDKs are linked via local `file:` paths. Build them once before
installing this app:

```bash
(cd ../../../sdk/javascript && npm ci && npm run build)
(cd ../../../sdk/react      && npm ci && npm run build)
```

Then install:

```bash
cp .env.example .env.local   # tweak if your Phoenix host differs
npm install
```

## Run

```bash
# Terminal 1: Phoenix
cd ../../../cachepuppy_core && mix phx.server   # or `docker compose up`

# Terminal 2: Next.js
npm run dev
```

Open <http://localhost:3000>, enter a name + colour + room, and the three
modules appear inside the room.

## Configuration (`.env.local`)

| Variable                    | Used by         | Default                                        |
| --------------------------- | --------------- | ---------------------------------------------- |
| `NEXT_PUBLIC_WS_URL`        | Browser SDK     | `ws://127.0.0.1:4000/socket/websocket`         |
| `CACHEPUPPY_API_BASE`       | API routes      | `http://127.0.0.1:4000`                        |
| `WORKFLOW_DEMO_PUBLIC_URL`  | API routes      | `http://127.0.0.1:3000`                        |
| `WORKFLOW_STEP_DELAY_MS`    | API routes      | `5000`                                         |

`WORKFLOW_DEMO_PUBLIC_URL` must be reachable from the Phoenix node (it is the
URL Phoenix posts back to for each workflow step). On Docker Desktop use
`http://host.docker.internal:3000`.

## Folder layout

```
src/
  app/
    page.tsx              # Login (name + colour + room)
    room/
      layout.tsx          # Mounts CachePuppyProvider + room chrome
      page.tsx            # 3 module cards
      cache/page.tsx      # Module 1 — caching CRUD with TTL
      realtime/page.tsx   # Module 2 — live cursors
      workflows/page.tsx  # Module 3 — 7 scenarios
    api/workflows/
      scenarioN/<step>/route.ts   # one POST handler per step
  lib/                    # admin client singleton, env, delay, retry state, …
  components/             # LoginCard, RoomShell, CachePanel, CursorBoard, …
  context/SessionContext.tsx
```

## Notes

- The `@cachepuppy/core` admin client uses Phoenix over HTTP, so all API routes
  are pinned to `runtime = "nodejs"`.
- Flaky-step counters (`flakySearchB1Attempts` / `scenario7BranchAttempts`)
  live on `globalThis` so they survive Next.js HMR mid-workflow.
- Sticky-notes / `setTopicState` is intentionally not implemented here.
