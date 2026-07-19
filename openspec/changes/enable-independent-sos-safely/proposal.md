## Why

The backend accepts emergency triggers from blind-runner and volunteer tokens and owns emergency-contact SMS escalation, but the current iOS release intentionally hides both emergency entries. The approved scope is now narrower and safer than the earlier independent-SOS proposal: only the two participants of an `IN_PROGRESS` run may initiate an order-associated SOS, and the app must not claim SMS success until a backend event confirms it.

The existing change ID is retained for continuity, but its former independent blind-runner capability is replaced by a dual-role in-run safety flow.

## What Changes

- **BREAKING** Remove the proposed always-reachable/no-order blind SOS and enable an SOS entry only for the associated blind runner and volunteer while canonical order status is `IN_PROGRESS`.
- Require the exact project-mandated second-confirmation text before every trigger.
- Submit the owned `orderId` and a fresh real GCJ-02 GPS coordinate from the live escort session to `POST /api/emergency/trigger`.
- Treat trigger success as a separate emergency event keyed by backend `eventId`; never synthesize or mutate `RunOrderStatus`.
- Present “联系人已收到短信” only after an event-ID-matching backend contact-notification message whose contract confirms successful SMS notification; trigger acknowledgement alone shows only submitted/processing state.
- Route the same pending, failed, contact-notified, and resolved safety state across both role experiences through the app-lifetime realtime coordinator.
- Keep SMS delivery, reverse geocoding, emergency-contact selection, CS escalation, schedulers, and rescue operations backend-owned.

## Capabilities

### New Capabilities

- `in-run-dual-role-sos`: Defines dual-role `IN_PROGRESS` eligibility, exact confirmation, required order/current-GPS association, event state, backend-confirmed SMS copy, accessibility, and unchanged order lifecycle.

### Modified Capabilities

- `formal-dispatch-service-flow`: Replaces the current hidden emergency requirement with the approved `IN_PROGRESS`-only dual-role entry.
- `backend-api-contract`: Defines both-role trigger authorization, structured trigger result, GCJ-02 fields, event recovery, and typed contact-notified/resolved WebSocket messages for both participants.
- `global-realtime-notification-handling`: Routes emergency events by event/order/role independently of screen lifetime.

## Impact

- iOS safety/UI/state: blind and volunteer in-run screens, shared emergency coordinator, location snapshot handling, AppState/realtime coordination, TTS, VoiceOver, Mock state, and session cleanup.
- Contracts: `/api/emergency/trigger`, structured trigger response/errors, both-role notification delivery, SMS-notification semantics, recovery after reconnect/relaunch, and no order-status mutation.
- Dependencies: requires `complete-realtime-fallback-and-notifications` and `enable-live-escort-location-and-track-summary`; the latter supplies fresh GCJ-02 service location and background continuity.
- Documentation/release: `AGENTS.md`, maintained docs, OpenAPI, WebSocket protocol, safety copy, failure behavior, privacy, and supervised real-device acceptance must be updated before UI enablement.
