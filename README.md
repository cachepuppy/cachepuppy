# Cachepuppy Monorepo

This repository contains the API-first scaffold for Beamline.

## Packages

- `cachepuppy_core`: Future Elixir/Phoenix backend (design docs only in this phase).
- `sdk/javascript` (`cachepuppy-js-sdk`): TypeScript SDK for Node.js and browser clients.
- `example/javascript_demo`: Frontend-only demo app that uses the SDK.

## JavaScript (SDK + demo)

There is no npm workspace at the repository root. Build and run from each package directory (use `npm ci` in CI, `npm install` locally).

1. SDK: `cd sdk/javascript && npm ci && npm run build`
2. Demo: `cd example/javascript_demo/frontend && npm ci && npm run build && npm start` (requires Phoenix running; see `example/javascript_demo/README.md`)

## Build Order

1. API design and protocol contracts
2. Demo app usage contract
3. SDK implementation with a mock transport
4. Demo integration against the mock transport
