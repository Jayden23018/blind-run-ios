## 1. Documentation And Contracts

- [x] 1.1 Update product/user-story/flow/page docs to describe backend system dispatch instead of volunteer self-selection.
- [x] 1.2 Update API and WebSocket docs with `dispatch-summary`, `NEW_ORDER` coordinates, not-available reasons, and temporary points behavior.
- [x] 1.3 Update iOS architecture and UI handoff docs to remove public order pool as the primary volunteer experience.

## 2. Shared Models And Mock Data

- [x] 2.1 Add Swift models for volunteer dispatch summary, summary active orders, summary recent orders, and not-available reasons.
- [x] 2.2 Extend `WSNewOrder` to decode timestamp, `startLatitude`, and `startLongitude`.
- [x] 2.3 Extend `MockAPIClient` to serve `GET /api/volunteer/dispatch-summary` and mock system-dispatch data.

## 3. Volunteer System Dispatch UI

- [x] 3.1 Refactor `VolunteerHomeViewModel` to load dispatch summary and derive readiness text, temporary points, completion count, and recent-order display data.
- [x] 3.2 Refactor `VolunteerHomeView` from nearby-order browsing to a dispatch workbench with availability, coverage, stats, active order, and recent orders.
- [x] 3.3 Remove public-order-list entry points from the primary volunteer home flow while preserving accepted/current order navigation.
- [x] 3.4 Update the `NEW_ORDER` prompt to show optional coordinates and keep only accept/decline behavior.

## 4. Blind Runner Dispatch Waiting UI

- [x] 4.1 Update blind-runner pending-match status copy, status replay text, and TTS to describe system dispatch.
- [x] 4.2 Ensure blind-runner order status handling covers `NO_VOLUNTEER`, accepted, en-route, arrived, in-progress, completed, cancelled, and emergency flows without exposing dispatch rounds.
- [x] 4.3 Keep volunteer location display and fallback behavior aligned with `/ws/blind` and `GET /api/blind/volunteer-location`.

## 5. Tests And Validation

- [x] 5.1 Add or update unit tests for dispatch summary decoding, temporary points calculation, not-available reason copy, and `NEW_ORDER` coordinate decoding.
- [x] 5.2 Add or update blind-runner tests for system-dispatch pending copy and no-volunteer handling.
- [x] 5.3 Run OpenSpec validation, docs validation, and focused iOS tests.

Validation note: `openspec validate adopt-system-dispatch-flow --strict --no-interactive`, `node scripts/validate-docs.mjs`, and `xcodebuild build-for-testing -workspace blindRun.xcworkspace -scheme blindRun -destination 'generic/platform=iOS'` passed. `xcodebuild test -workspace blindRun.xcworkspace -scheme blindRun -destination 'platform=iOS,name=111'` passed with 11 UI tests executed, 1 UI test skipped, 65 unit tests executed, and 1 unit test skipped. `xcodebuild test -workspace blindRun.xcworkspace -scheme blindRun -destination 'platform=iOS,name=iPad Pro (2)'` passed with 11 UI tests executed, 1 UI test skipped, 65 unit tests executed, and 1 unit test skipped.
