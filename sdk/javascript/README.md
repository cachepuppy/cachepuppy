# cachepuppy-js-sdk

TypeScript SDK that gives JavaScript developers access to CachePuppy websocket capabilities.

This package provides:

- Client lifecycle management
- Topic publish/subscribe
- Per-topic shared state helpers (`setTopicState`, `getTopicState`, `closeTopic`)
- Per-connection private session state via the fixed `session` channel (`setSessionState`, `getSessionState`; no room topic)
- `onStateUpdated` helper for `state_updated` topic events
- Mock transport for local development and demo flows

See `docs/api-design.md` for the API contract.
