## Why

The product decision has changed from volunteer self-selection in a public order pool to backend-controlled system dispatch. The iOS client and project documentation still describe nearby order browsing as the main volunteer experience, which now conflicts with the real backend contract and the intended blind-runner waiting flow.

## What Changes

- **BREAKING**: Remove the public order pool / volunteer self-selection experience from the primary volunteer flow.
- Replace the volunteer home page with a system-dispatch workbench driven by `GET /api/volunteer/dispatch-summary`.
- Keep the volunteer availability switch as the explicit opt-in for receiving backend dispatches.
- Handle `NEW_ORDER` WebSocket dispatches as 30-second accept/decline prompts; no "later" business action is supported.
- Update blind-runner waiting copy and TTS from "waiting for volunteers to browse and accept" to "system dispatch in progress".
- Keep blind-runner booking, cancellation, emergency, status polling/WebSocket fallback, and completion review flows aligned with the existing order state machine.
- Document the new dispatch-summary contract, `NEW_ORDER` coordinates, temporary points display, and remaining backend confirmations.

## Capabilities

### New Capabilities
- `system-dispatch-flow`: Covers backend-controlled dispatch behavior across blind-runner waiting states, volunteer availability, dispatch summary, WebSocket `NEW_ORDER` prompts, and the removal of the public order pool as the primary volunteer experience.

### Modified Capabilities
- None.

## Impact

- Documentation: `docs/03-user-stories.md`, `docs/04-user-flows-and-state-machine.md`, `docs/05-page-specs.md`, `docs/06-data-model.md`, `docs/07-api-contract.openapi.yaml`, `docs/08-ios-architecture.md`, `docs/websocket-protocol.md`, and `docs/ui/ui-handoff-ios.md` need updates to match system dispatch.
- iOS models: add dispatch-summary response models, expand `NEW_ORDER` with `timestamp`, `startLatitude`, and `startLongitude`, and tolerate summary-specific order fields.
- Volunteer UI: refactor the volunteer home page away from nearby order browsing toward dispatch readiness, coverage, stats, active order, and recent orders.
- Blind-runner UI: update matching/waiting copy, status replay text, and TTS to describe backend system dispatch.
- Mock/test support: extend `MockAPIClient` and unit tests for dispatch summary, temporary points, readiness reasons, and WebSocket dispatch prompts.
- Backend integration: real HTTP remains `http://47.114.113.171`; no backend code is added to this repository.
