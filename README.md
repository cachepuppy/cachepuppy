# Beamline Monorepo

This repository contains the API-first scaffold for Beamline.

## Packages

- `beamline_core`: Future Elixir/Phoenix backend (design docs only in this phase).
- `beamline_js_sdk`: TypeScript SDK for Node.js and browser clients.
- `beamline_demo_app`: Frontend-only demo app that uses the SDK.

## Build Order

1. API design and protocol contracts
2. Demo app usage contract
3. SDK implementation with a mock transport
4. Demo integration against the mock transport
