## Why

The current iOS implementation still has gaps around the formal blind-runner and volunteer service lifecycle: completed service, rating, volunteer review gating, and the strict `DRIVER_ARRIVED -> IN_PROGRESS -> COMPLETED` state path are not fully enforced in code. This change aligns both client roles with the production dispatch flow before release validation against the real cloud backend.

## What Changes

- Add a formal blind-runner flow from login, role selection, profile and emergency contact completion, booking, status tracking, in-service state, completion, and optional rating.
- Add a formal volunteer flow from login, role selection, profile, certification/admin review gating, manual dispatch opt-in, WebSocket/location readiness, timed `NEW_ORDER` prompts, accepted order handling, service progression, completion, points, and records.
- Enforce the strict service state machine: `DRIVER_ARRIVED` must wait for `IN_PROGRESS`; only `IN_PROGRESS` may show or execute finish service.
- Update iOS code so `DRIVER_ARRIVED` cannot directly call `/api/orders/{id}/finish`.
- Keep emergency UI as a placeholder for this change; do not launch a real emergency backend flow beyond existing guarded placeholder behavior unless a separate safety change re-enables it.
- Update tests and docs so release validation covers the formal dispatch lifecycle and the strict completion gate.

## Capabilities

### New Capabilities

- `formal-dispatch-service-flow`: Defines the production blind-runner and volunteer service lifecycle, including role/profile gates, system dispatch readiness, timed dispatch response, strict order-state progression, completion, rating, and placeholder emergency behavior.

### Modified Capabilities

- None.

## Impact

- Affected iOS modules: `BlindRunner`, `Volunteer`, `Role`, `Profile`, `Orders`, `Core/Models`, `MockAPIClient`, `WebSocketService` consumers, `Voice`, and UI tests.
- Affected docs: `docs/04-user-flows-and-state-machine.md`, `docs/05-page-specs.md`, `docs/06-data-model.md`, `docs/08-ios-architecture.md`, `docs/09-accessibility-and-voice-guidelines.md`, and `docs/10-ai-coding-tasks.md`.
- Affected API usage: existing cloud endpoints only, including `/api/orders`, `/api/orders/{id}`, `/api/orders/{id}/respond`, `/api/orders/{id}/en-route`, `/api/orders/{id}/arrived`, `/api/orders/{id}/finish`, `/api/orders/{id}/review`, `/api/orders/mine`, `/api/volunteer/dispatch-summary`, `/api/volunteer/dispatch-status`, `/api/user/role`, and WebSocket `/ws/blind` and `/ws/volunteer`.
- No backend implementation, database configuration, local server, new role, route navigation, real-time track sharing, payment, or production emergency workflow is added to this repository.
