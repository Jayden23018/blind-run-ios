## 1. Safety Preconditions And Contract Confirmation

- [ ] 1.1 Complete and validate `complete-realtime-fallback-and-notifications` so emergency events have one app-lifetime, event-ID-aware routing owner.
- [ ] 1.2 Obtain human/product/compliance confirmation for no-order confirmation wording, success/no-location/offline/cooldown/escalation/resolution copy, and any approved external emergency guidance.
- [ ] 1.3 Obtain backend confirmation for eligible order association, structured trigger/status enums, cooldown and repeated-trigger semantics, event recovery after relaunch, volunteer response authorization/idempotency/timeout, and typed WebSocket follow-up messages.
- [ ] 1.4 Keep release-facing SOS entry disabled until tasks 1.2 and 1.3 are resolved; record every missing API/behavior as `需要人工确认` rather than inventing client behavior.

## 2. Canonical Documentation And Contracts

- [ ] 2.1 Update `AGENTS.md` to replace the current hidden-emergency release rule only after the dedicated safety decisions are approved, preserving exact required confirmation copy or adding an explicitly approved no-order variant.
- [ ] 2.2 Update `plan.md`, the canonical `formal-dispatch-service-flow` purpose and cancellation wording, and product/scope/story/flow/page/data/architecture/accessibility/task docs with independent SOS, event states, responsibility boundaries, privacy, offline behavior, and release risks.
- [ ] 2.3 Update `docs/07-api-contract.openapi.yaml` with optional trigger fields, `EmergencyTriggerResponse`, cooldown/errors, event recovery, volunteer response, ownership, idempotency, and no-order-status-mutation semantics.
- [ ] 2.4 Update `docs/websocket-protocol.md` with typed event-ID-keyed pending/contact-notified/escalated/resolved/false-alarm messages and volunteer alert/response timing.

## 3. Models And Mock Safety State

- [ ] 3.1 Make the SOS request fields optional and add typed trigger response, event status, cooldown, recovery, volunteer action/result, and WebSocket follow-up models.
- [ ] 3.2 Add stable emergency error mappings and authoritative retry parsing without reusing an unrelated local countdown.
- [ ] 3.3 Implement Mock independent/order-associated triggers, no-location success, duplicate/cooldown, failure, contact notification, escalation, resolution, volunteer responses/timeouts, and event recovery without changing `RunOrderStatus`.

## 4. Emergency Coordination

- [ ] 4.1 Implement an `EmergencyCoordinator` integrated with the global realtime coordinator and keyed by backend event ID, with duplicate-submit protection and no order-state ownership.
- [ ] 4.2 Select `orderId` only for owned `DRIVER_EN_ROUTE`, `DRIVER_ARRIVED`, or `IN_PROGRESS` orders and omit it in every other state.
- [ ] 4.3 Include current device GPS only when authorized/available, omit both GPS fields otherwise, and prohibit SOS-blocking reverse-geocode work.
- [ ] 4.4 Persist only approved non-secret event recovery metadata keyed by authenticated user ID, clear it on logout/account deletion/session expiration/user change, and recover authoritative state after navigation, reconnect, and relaunch before presenting it as current.
- [ ] 4.5 Implement authoritative cooldown/retry and explicit unsent/error states that never imply backend receipt after failure.

## 5. Blind-Runner SOS Experience

- [ ] 5.1 Add a consistent 64pt+ SOS entry to every authenticated blind-role root flow, including incomplete profile/identity/contact onboarding and no-order home.
- [ ] 5.2 Require the approved exact second-confirmation copy, disable duplicate confirmation while submitting, and make cancellation issue no request.
- [ ] 5.3 Build visible/TTS/VoiceOver presentation for submitting, pending, location-included/no-location, cooldown, unsent, contact-notified, escalated, resolved, and recovery states.
- [ ] 5.4 Integrate emergency state into repeat-current-status without replacing or mutating canonical order-status announcements.

## 6. Volunteer Emergency Response

- [ ] 6.1 Present `EMERGENCY_VOLUNTEER_ALERT` as a high-priority event-ID-keyed alert only to the associated volunteer and retain it across navigation.
- [ ] 6.2 Add separate second confirmations for `NEED_HELP` and `FALSE_ALARM`, call the query-parameter response endpoint, and present only backend-confirmed outcomes.
- [ ] 6.3 Display the backend-owned response deadline and escalation copy without running a client scheduler or claiming local escalation.
- [ ] 6.4 Keep blind-user GPS private: do not render raw coordinates, a live marker, direction, route, or track; use only approved backend safety/location text.

## 7. Safety, Accessibility, And Privacy Tests

- [ ] 7.1 Add unit tests for optional request encoding, eligible order association, structured success gating, cooldown, duplicate suppression, event-ID routing/recovery, cross-account metadata isolation and cleanup, and unchanged order status.
- [ ] 7.2 Add Mock/UI tests for SOS reachability across blind flows, exact confirmation copy, cancel/no-request, no-location success, offline unsent state, cooldown, resolution, and repeat status.
- [ ] 7.3 Add volunteer tests for authorization, response confirmations, timeout presentation, false-alarm handling, and distinct safety event IDs.
- [ ] 7.4 Add privacy/accessibility assertions that raw emergency coordinates are absent from visible text, logs, screenshots, maps, and accessibility output and that all safety states have equivalent VoiceOver/TTS feedback.

## 8. Release Validation And Enablement

- [ ] 8.1 Extend cloud probes for independent and eligible-order SOS, optional GPS, cooldown, recovery, volunteer response, contact escalation, and no order-status mutation without adding backend code.
- [ ] 8.2 Run `node scripts/validate-docs.mjs` and `openspec validate enable-independent-sos-safely --strict --no-interactive`.
- [ ] 8.3 Run focused unit/UI tests, baseline tests on `111` and `iPad Pro (2)`, and supervised dual-device real-backend safety acceptance including offline/location-denied cases.
- [ ] 8.4 Record product/compliance approval, backend contract evidence, privacy review, failure screenshots/logs, and real-device results before enabling SOS in Demo and Production builds.
- [ ] 8.5 Verify rollback hides entry without deleting already recorded backend emergency events and document the rollback decision path.
