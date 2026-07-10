## Why

The backend now supports an independent SOS event with or without an active order, location degradation, contact escalation, cooldown, and real-time follow-up. The current iOS release intentionally hides emergency entry points, so enabling SOS requires a dedicated safety change rather than a simple button activation.

## What Changes

- **BREAKING** Replace the current hidden/deferred emergency UI requirement with an approved blind-runner SOS flow available both with and without an active order.
- Add an always-reachable, accessible blind-runner SOS entry that requires the exact second-confirmation copy mandated by `AGENTS.md` before calling `POST /api/emergency/trigger`.
- Make `orderId`, `gpsLat`, and `gpsLng` optional in the client request; include `orderId` only for an eligible active order and use current authorized GPS when available.
- Decode and retain `success`, `eventId`, and `status`, scope any persisted recovery metadata to the authenticated user, clear it with session cleanup, and present explicit submitted, pending, escalated, resolved, cooldown, failure, and offline states without changing the order lifecycle status.
- Handle no-coordinate requests and explain that the backend will apply its address/coordinate/text fallback rather than claiming precise rescue location.
- Consume emergency WebSocket follow-up events and support the volunteer response contract when an associated volunteer is alerted.
- Keep administrator/CS rescue operations, SMS delivery, reverse geocoding, timeout escalation, and scheduler behavior backend-owned.
- Continue using real post-accept phone numbers; do not introduce virtual-number scope in this safety change.
- Preserve the decision not to display another person's real-time coordinate, marker, route, or track; emergency participants receive only approved safety text and state.

## Capabilities

### New Capabilities

- `independent-sos-safety`: Defines blind-runner independent and order-associated SOS initiation, confirmation, state presentation, cooldown, location degradation, volunteer follow-up, accessibility, and safety language.

### Modified Capabilities

- `formal-dispatch-service-flow`: Replaces the current release-wide hidden emergency requirement with the approved SOS entry while keeping emergency separate from order status.
- `backend-api-contract`: Clarifies the optional SOS request fields, structured trigger response, cooldown/error contract, and volunteer response endpoints/messages consumed by iOS.

## Impact

- iOS safety/UI/state: `SafetyModule`, blind-runner home and active-order flows, volunteer service flow, AppState/global event coordination, location permission handling, TTS, and VoiceOver.
- API/WebSocket contracts: `/api/emergency/trigger`, `/api/emergency/{eventId}/volunteer-response`, emergency notification messages, structured response/error schemas, and cooldown semantics.
- Documentation/compliance: `AGENTS.md`, product/scope/page/flow/accessibility docs, OpenAPI, WebSocket protocol, responsibility language, and release risk must be updated together before UI enablement.
- Tests and validation: Mock state machine, failure/cooldown/no-location cases, exact confirmation copy, no order-status mutation, notification escalation, cloud contract probes, and real-device safety acceptance on `111` and `iPad Pro (2)`.
- Sequencing: implement `complete-realtime-fallback-and-notifications` first so SOS event IDs, priority, and navigation-independent delivery have one app-lifetime owner.
