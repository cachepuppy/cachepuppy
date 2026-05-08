# Workflows demo — Node server

Implements the four e2e scenario flows (serial, static parallel + merge, dynamic parallel + merge, parallel + summary merge) under `/scenario1` … `/scenario4`.

## Environment

Copy `.env.example` or set:

- `PORT` — listen port (default `8787`)
- `CACHEPUPPY_API_BASE` — CachePuppy HTTP origin (default `http://127.0.0.1:4000`)
- `WORKFLOW_DEMO_PUBLIC_URL` — public base URL for workflow step callbacks (must be reachable from CachePuppy):
  - local Phoenix: `http://127.0.0.1:${PORT}`
  - Docker Phoenix (Docker Desktop): `http://host.docker.internal:${PORT}`
- `WORKFLOW_STEP_DELAY_MS` — artificial delay per scenario endpoint for visible workflow progression in UI (default `5000`)

## Run

```bash
npm install
npm start
```
