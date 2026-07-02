## 1. State Machine and Models

- [x] 1.1 Add shared `RunOrderStatus` helpers for formal routing, finish eligibility, arrived-waiting copy, and emergency placeholder visibility.
- [x] 1.2 Update `VolunteerProfileResponse` and related profile logic to decode and expose `adminReviewStatus` when the backend returns it.
- [x] 1.3 Update volunteer readiness guards so accepting dispatches requires complete profile, certification approval, administrator approval when available, availability opt-in, and location permission.
- [x] 1.4 Ensure all non-Mock API and WebSocket usage remains fixed to `http://47.114.113.171` and `ws://47.114.113.171`.

## 2. Blind Runner Flow

- [x] 2.1 Add or refactor blind-runner routing so active order status routes to waiting/status, in-service, completion/rating, or terminal views as specified.
- [x] 2.2 Implement the blind-runner in-service experience for `IN_PROGRESS`, including polling/WebSocket updates, TTS, repeat status, and service-completed transition.
- [x] 2.3 Implement the blind-runner completion/rating experience for `COMPLETED`, including optional `POST /api/orders/{id}/review` submission and skip/return-home behavior.
- [x] 2.4 Keep blind-runner booking gates for profile, emergency contact, location permission, start location, and 30-minute appointment lead time intact and covered by tests.
- [x] 2.5 Convert emergency action behavior in the blind-runner flow to a clearly placeholder/deferred experience for this change, without implying a real emergency backend workflow completed.
- [x] 2.6 Add a blind-runner cancel escape action for `REMATCHING` orders on both home and order status views, using the existing cancel endpoint with second confirmation.

## 3. Volunteer Flow

- [x] 3.1 Keep volunteer home centered on `/api/volunteer/dispatch-summary`, manual availability opt-in, WebSocket online state, and location reporting.
- [x] 3.2 Ensure `NEW_ORDER` prompts show the required dispatch fields, run the response countdown, accept with location pre-report, decline on user action or timeout, and use `/api/orders/{id}/respond`.
- [x] 3.3 Update accepted-order routing so `PENDING_ACCEPT`, `DRIVER_EN_ROUTE`, `DRIVER_ARRIVED`, and `IN_PROGRESS` have correct service states and copy.
- [x] 3.4 Remove finish-service UI and API execution from `DRIVER_ARRIVED`; show an arrived/waiting-for-service-start state and continue polling/listening for `IN_PROGRESS`.
- [x] 3.5 Gate `/api/orders/{id}/finish` in the ViewModel so it can only execute when the current order status is `IN_PROGRESS`.
- [x] 3.6 Keep service completion confirmation for `IN_PROGRESS` and update the completion result to refresh active order, points, and service records.
- [x] 3.7 Convert emergency action behavior in the volunteer flow to a clearly placeholder/deferred experience for this change, without implementing volunteer emergency response.
- [x] 3.8 Add the volunteer go-to-start-location service state with current/start map markers and external walking navigation via installed map apps.
- [x] 3.9 Route dispatch acceptance directly into the volunteer service flow, refresh accepted order/dispatch summary, and keep service-flow map focused on the red start-location marker.

## 4. Mock and Tests

- [x] 4.1 Update `MockAPIClient` order transitions so `/finish` rejects `DRIVER_ARRIVED` and only succeeds from `IN_PROGRESS`.
- [x] 4.2 Add or update unit tests for `RunOrderStatus` routing, finish eligibility, cancellation eligibility, and emergency placeholder eligibility.
- [x] 4.3 Add or update unit tests for volunteer profile/admin-review readiness and accept-block messages.
- [x] 4.4 Add or update unit tests for `NEW_ORDER` accept, decline, timeout, and location pre-report behavior.
- [x] 4.5 Add or update blind-runner tests for booking gates, in-service routing, completion/rating, review request submission, and repeat-status TTS.
- [x] 4.6 Add or update volunteer tests for arrived waiting state, blocked finish from `DRIVER_ARRIVED`, allowed finish from `IN_PROGRESS`, and post-completion refresh behavior.
- [x] 4.7 Add or update UI tests or smoke tests for the formal two-role happy path in Mock and Demo Cloud where feasible.
- [x] 4.8 Add unit tests for external map URL construction, third-party map availability filtering, volunteer map markers, and blind-runner active-order polling interval.
- [x] 4.9 Add unit tests for dispatch acceptance initial order refresh, dispatch map dual markers, service-flow start marker priority, volunteer service action labels, and stable `REMATCHING` blind-runner copy.
- [x] 4.10 Add unit tests that `REMATCHING` is cancellable and shows the blind-runner cancel action.

## 5. Documentation

- [x] 5.1 Update `docs/04-user-flows-and-state-machine.md` to make `DRIVER_ARRIVED -> IN_PROGRESS -> COMPLETED` strict and describe completion/rating routing.
- [x] 5.2 Update `docs/05-page-specs.md` for blind-runner in-service, completion/rating, volunteer arrived waiting state, and emergency placeholder behavior.
- [x] 5.3 Update `docs/06-data-model.md` for volunteer `adminReviewStatus`, strict finish eligibility, review submission, and deferred production emergency behavior.
- [x] 5.4 Update `docs/08-ios-architecture.md`, `docs/09-accessibility-and-voice-guidelines.md`, and `docs/10-ai-coding-tasks.md` for the formal lifecycle, strict finish gate, and placeholder emergency scope.
- [x] 5.5 Record any backend contract dependency that needs human confirmation, especially automatic transition from `DRIVER_ARRIVED` to `IN_PROGRESS`.
- [x] 5.6 Record that accepting dispatch must not skip directly to `IN_PROGRESS`, and that `REMATCHING` should first be investigated as a volunteer-cancel-after-acceptance path.
- [x] 5.7 Record the backend-confirmed `/api/orders/{id}/cancel` support for `REMATCHING`, including the requirement to use the blind-runner token rather than the former volunteer token.

## 6. Validation

- [x] 6.1 Run `openspec validate enforce-formal-dispatch-service-flow --strict --no-interactive`.
- [x] 6.2 Run `node scripts/validate-docs.mjs`.
- [x] 6.3 Run focused unit tests for state machine, profile gating, dispatch prompt response, Mock transitions, and review submission.
- [ ] 6.4 Run `xcodebuild test -workspace blindRun.xcworkspace -scheme blindRun -destination 'platform=iOS,name=111'` when device `111` is available.
- [ ] 6.5 Run `xcodebuild test -workspace blindRun.xcworkspace -scheme blindRun -destination 'platform=iOS,name=iPad Pro (2)'` when device `iPad Pro (2)` is available.
- [ ] 6.6 Run production-readiness validation with real AMap/cloud flags before release sign-off.
