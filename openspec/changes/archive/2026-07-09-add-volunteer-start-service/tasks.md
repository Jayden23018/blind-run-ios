## 1. Contract and Documentation

- [x] 1.1 Update AGENTS.md, OpenSpec, OpenAPI, and maintained docs to describe `POST /api/orders/{id}/start-service`.
- [x] 1.2 Remove or replace maintained-doc statements that say `DRIVER_ARRIVED -> IN_PROGRESS` is cloud-only or has no iOS start-service endpoint.

## 2. iOS Client and Mock

- [x] 2.1 Add volunteer ViewModel support for `startService()` and call `/api/orders/{id}/start-service`.
- [x] 2.2 Show a 64pt volunteer "开始服务" action in `DRIVER_ARRIVED`, while keeping `/finish` visible only in `IN_PROGRESS`.
- [x] 2.3 Update MockAPIClient to support the formal `/start-service` route and remove test/debug reliance on `/mock-start-service`.

## 3. Tests and E2E

- [x] 3.1 Update unit tests for `arrived -> start-service -> finish`, blocked finish from `DRIVER_ARRIVED`, and volunteer action labels.
- [x] 3.2 Update cloud E2E to call `/start-service` after `/arrived` and before `/finish`.
- [x] 3.3 Run OpenSpec validation, docs validation, and iOS tests where available.
