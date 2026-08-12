## Why

The cloud backend only dispatches orders to online volunteers whose latest WebSocket location is within 10 km of the order start point. The iOS client and cloud E2E script must make this dispatch precondition explicit before reading available orders or responding to a dispatch.

## What Changes

- Document that volunteer dispatch requires `/ws/volunteer` plus `LOCATION_UPDATE` before `/api/orders/available` or `/respond`.
- Send a volunteer location update immediately before loading available orders and before accepting an order when location is authorized.
- Update cloud E2E to wait for dispatch readiness before calling `/respond`.
- Keep the existing WebSocket location message shape and avoid restoring deprecated REST location fallback.

## Impact

- Touches volunteer list/detail flows, WebSocket location reporting helpers, cloud E2E tooling, maintained docs, and focused tests.
- Keeps backend dispatch ownership outside this repository.
