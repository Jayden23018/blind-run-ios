## Why

The backend has confirmed the iOS v2 service lifecycle is volunteer-driven through an explicit start-service step. After a volunteer arrives, the client must call `POST /api/orders/{id}/start-service` before finishing the service. The previous documents and client behavior treated `DRIVER_ARRIVED -> IN_PROGRESS` as a cloud-pushed transition, which leaves the volunteer unable to continue the order from the arrived state.

## What Changes

- Add `POST /api/orders/{id}/start-service` as the volunteer action that moves `DRIVER_ARRIVED -> IN_PROGRESS`.
- Keep blind-runner behavior passive: blind-runner UI receives status changes through WebSocket or polling and does not show a start-service confirmation action.
- Keep `/api/orders/{id}/finish` gated to `IN_PROGRESS`; the client must not finish directly from `DRIVER_ARRIVED`.
- Update iOS volunteer UI, Mock, tests, cloud E2E, OpenAPI, and maintained docs to use the explicit start-service step.

## Impact

- Touches volunteer service flow, Mock API routing, unit tests, cloud E2E, OpenAPI contract, OpenSpec, and maintained lifecycle docs.
- Does not add backend implementation code to this iOS repository.
