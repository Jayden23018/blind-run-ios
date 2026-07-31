## 1. iOS Registration Flow

- [x] 1.1 Reduce the registration step model and indicator to basic identity and face verification, with separate syncing and completed result states.
- [x] 1.2 Remove training/quiz ViewModel state, actions, UI, polling conditions, and API calls while preserving backend-authoritative completion refresh.
- [x] 1.3 Remove training DTOs and unused training fields from the iOS registration models.

## 2. Offline Mock and Tests

- [x] 2.1 Make Mock face verification directly produce `STEP_4_COMPLETED` and `canAcceptOrders = true` without enabling availability, and remove Mock training routes/state.
- [x] 2.2 Update unit tests for two-step routing, completed and syncing states, legacy `STEP_4_TRAINING`, no training requests, and Mock direct completion.
- [x] 2.3 Add or update UI assertions for the two-step flow, absent training controls, accessible success copy, and manual availability behavior.

## 3. Contracts and Documentation

- [x] 3.1 Update maintained page and data-model documentation for direct completion after face verification and legacy-state migration requirements.
- [x] 3.2 Mark every volunteer/admin training OpenAPI operation deprecated, document legacy training schemas/status fields, and specify atomic Step 3 completion.
- [x] 3.3 Replace the WebSocket training-completion notification copy with volunteer-registration completion copy.

## 4. Validation

- [x] 4.1 Validate the OpenSpec change and maintained documentation.
- [x] 4.2 Run relevant iOS tests and record any real-backend or real-device validation that remains blocked on external deployment.

## 5. Legacy Completion Compatibility

- [x] 5.1 Treat legacy `STEP_4_TRAINING` as completed registration across status models, AppState, volunteer home, and action guards without enabling availability.
- [x] 5.2 Update unit and UI coverage so legacy training status reaches the completion page, stops polling, returns home, and still requires manual availability.
- [x] 5.3 Update OpenSpec and maintained contract documentation, then rerun strict docs/OpenSpec validation and relevant tests on `111` and `iPad Pro (2)`.

## 6. Dispatch Readiness Diagnostics

- [x] 6.1 Refresh the volunteer dispatch summary every 10 seconds while the home screen is active and after WebSocket/location or availability readiness changes.
- [x] 6.2 Show an explicit backend-contract diagnostic when `canDispatch = false` has no `notAvailableReasons`, without synthesizing eligibility.
- [x] 6.3 Add a redacted, account-scoped cloud readiness probe that does not switch roles or mutate volunteer profile/availability.
- [x] 6.4 Add focused unit tests and document the real-account result plus any backend-owned remediation still requiring human confirmation.
