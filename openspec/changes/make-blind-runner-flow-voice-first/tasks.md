## 1. Specs And Documentation

- [x] 1.1 Update `docs/05-page-specs.md` so blind-runner home and booking are voice-first, with map content defined as auxiliary rather than first-priority content.
- [x] 1.2 Update `docs/09-accessibility-and-voice-guidelines.md` with guided booking repeat-status, map-as-auxiliary semantics, location fallback speech, and no-speech-spam rules.
- [x] 1.3 Update `docs/03-user-stories.md` and `docs/04-user-flows-and-state-machine.md` to describe the guided blind-runner booking flow without changing canonical order statuses.
- [x] 1.4 Clean stale UI handoff/review checklist text that still implies map-first blind-runner layout, emergency UI availability, old cancellation states, or "正在赶来" copy for `PENDING_ACCEPT`.
- [x] 1.5 Record release risk and validation expectations for real AMap, VoiceOver, and dual-device checks in the relevant docs if implementation changes a release path.

## 2. Blind-Runner Home

- [x] 2.1 Reorder `BlindRunnerHomeView` so no-order status or active-order summary and the primary action appear before current-location text and map content.
- [x] 2.2 Move blind-runner home map content into an auxiliary region or expandable section that remains available for AMap validation but is not the first meaningful VoiceOver stop.
- [x] 2.3 Update home repeat-status copy to include current no-order or active-order state plus meaningful location/start-address context.
- [x] 2.4 Ensure home primary actions and cancellation controls keep 64pt+ touch targets, clear disabled/loading states, accessibility labels, and second-confirmation behavior.

## 3. Guided Booking Flow

- [x] 3.1 Add guided-step state to `BlindBookingViewModel` for start point, appointment time, optional running needs, and review/submit.
- [x] 3.2 Refactor `BlindBookingView` into guided step sections while keeping the existing `CreateOrderRequest` fields and API call unchanged.
- [x] 3.3 Preserve current-location reverse geocoding, AMap POI search, selected-place coordinates, and speech-triggered POI search behavior.
- [x] 3.4 Keep appointment time on the system `DatePicker` with the existing 30-minute minimum and no natural-language time parsing.
- [x] 3.5 Add concise step and review summaries for TTS/VoiceOver, including location source, selected address, appointment time, optional needs, and blocking errors.
- [x] 3.6 Keep optional needs optional and omit empty optional fields from review and repeat-status speech.
- [x] 3.7 Ensure map content on booking is auxiliary, does not expose raw coordinates, and clearly labels demo fallback or unresolved address states.

## 4. Order Status And Shared Presentation

- [x] 4.1 Verify `BlindOrderStatusView` presents status, next action, volunteer/contact/distance information, and repeat-status before any auxiliary map content if map content is added or retained there.
- [x] 4.2 Keep blind-runner lifecycle behavior unchanged for `PENDING_MATCH`, `PENDING_ACCEPT`, `DRIVER_EN_ROUTE`, `DRIVER_ARRIVED`, `IN_PROGRESS`, `COMPLETED`, `CANCELLED`, `REMATCHING`, and `NO_VOLUNTEER`.
- [x] 4.3 Preserve blind-runner cancellation visibility only for `PENDING_MATCH`, `PENDING_ACCEPT`, and `REMATCHING`.
- [x] 4.4 Add or reuse blind-runner-specific high-contrast, low-density presentation primitives without forcing volunteer screens into the same layout.
- [x] 4.5 Ensure important blind-runner TTS prompts also post VoiceOver announcements where required by docs.

## 5. Tests

- [x] 5.1 Add or update unit tests for guided booking step validation, submit readiness, and unchanged `CreateOrderRequest` payload fields.
- [x] 5.2 Add or update tests for repeat-status copy on blind-runner home and booking steps.
- [x] 5.3 Add or update tests for speech search completion, search result VoiceOver feedback, and no raw coordinate display in blind-runner UI.
- [x] 5.4 Add or update UI tests or accessibility assertions proving primary action/status precedes auxiliary map content in blind-runner VoiceOver traversal.
- [x] 5.5 Add or update tests that canonical order lifecycle, polling/WebSocket handling, hidden emergency UI, and cancellation permissions remain unchanged.

## 6. Validation

- [x] 6.1 Run `openspec validate make-blind-runner-flow-voice-first --strict --no-interactive`.
- [x] 6.2 Run `node scripts/validate-docs.mjs`.
- [ ] 6.3 Run focused unit/UI tests covering changed blind-runner home, booking, voice, and order-status behavior.
- [ ] 6.4 Run baseline real-device tests required by `AGENTS.md` when implementation changes release-facing flows.
- [ ] 6.5 Run real AMap and Demo Cloud smoke validation on device `111` and dual-device validation with `iPad Pro (2)` before release sign-off.
