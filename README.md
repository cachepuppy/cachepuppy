# Cachepuppy Monorepo

This repository contains the API-first scaffold for Beamline.

## Packages

- `cachepuppy_core`: Future Elixir/Phoenix backend (design docs only in this phase).
- `sdk/javascript` (`@cachepuppy/core`): TypeScript SDK for Node.js and browser clients.
- `sdk/react` (`@cachepuppy/react`): React hooks/provider wrapper over the core JavaScript SDK.
- `example/javascript_demo`: Interactive React demo app that uses the SDK packages.
- `cli` (`cachepuppy-cli`): Docker runtime CLI (single-node compose + volume) with `init/start/stop/reset/update/status/logs`.

## Documentation site

The Fumadocs + Next.js documentation lives in `docs/`. Run `cd docs && npm install && npm run dev` to preview it locally.

## JavaScript (SDK + demo)

There is no npm workspace at the repository root. Build and run from each package directory (use `npm ci` in CI, `npm install` locally).

1. SDKs: `cd sdk/javascript && npm ci && npm run build` and `cd sdk/react && npm ci && npm run build` (core first, then react)
2. Demo: `cd example/javascript_demo/interactive && npm ci && npm run dev` (requires Phoenix running; see `example/javascript_demo/README.md`)

## Build Order

1. API design and protocol contracts
2. Demo app usage contract
3. SDK implementation with a mock transport
4. Demo integration against the mock transport
