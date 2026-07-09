## Why

The cloud backend now handles volunteer order decisions through `POST /api/orders/{id}/respond`. The previous `/accept` and `/reject` endpoints are no longer active, so the iOS client and maintained contract documents must use the current endpoint to complete the MVP order flow.

## What Changes

- Replace volunteer accept calls with `POST /api/orders/{id}/respond`.
- Use `OrderRespondRequest(action)` with `ACCEPT` and `DECLINE`.
- Keep the existing MVP order status model unchanged.
- Update Mock, tests, E2E tooling, and maintained docs to match the cloud backend.

## Impact

- Touches the volunteer order flow, WebSocket dispatch response path, Mock API routing, cloud E2E script, OpenAPI contract, and related docs.
- Keeps backend ownership outside this repository.
