## Why

The blind-runner flow currently works functionally, but its information architecture still treats visual map panels and long forms as primary surfaces. Blind runners need the app to put current state, next action, spoken confirmation, and low-cognitive-load booking steps ahead of visual map inspection.

This change improves the blind-runner experience while preserving the existing AMap, real-location, REST, WebSocket, and order-state contracts required for release validation.

## What Changes

- Make the blind-runner home voice-first: current status or the next primary action appears before any map surface.
- Demote visual maps on blind-runner screens to auxiliary location confirmation, with textual/TTS location summaries as the primary user-facing signal.
- Replace the blind-runner booking long-form layout with a guided sequence: confirm start point, confirm appointment time, optionally add running needs, then review and submit.
- Preserve AMap POI search, reverse geocoding, real coordinates, map annotations, and location-permission gating for order creation and validation.
- Keep appointment time selection on the system `DatePicker`; do not add natural-language time parsing or a global AI assistant.
- Improve blind-runner TTS and VoiceOver copy for location source, selected start point, appointment time, optional needs, submit readiness, and repeat-status behavior.
- Add high-contrast blind-runner presentation requirements without forcing volunteer screens into the same visual density.
- Document and test that this change does not add backend endpoints, backend source code, route navigation, real-time track sharing, or emergency UI.

## Capabilities

### New Capabilities

- `blind-runner-voice-first-experience`: Defines voice-first blind-runner home, booking, map-as-auxiliary behavior, guided booking steps, high-contrast presentation, and repeat-status expectations.

### Modified Capabilities

- `formal-dispatch-service-flow`: Refines blind-runner booking and lifecycle presentation so the guided voice-first UI continues to satisfy existing profile, emergency-contact, location, appointment-time, order-status, polling, WebSocket, cancellation, completion, and hidden-emergency requirements.

## Impact

- iOS UI/ViewModels: `BlindRunnerHomeView`, `BlindBookingView`, `BlindOrderStatusView`, shared blind-runner components, and any supporting ViewModel state needed for guided booking steps.
- Map/location modules: keep existing AMap wrappers and location services, but adjust blind-runner placement and accessibility copy so map surfaces are auxiliary.
- Voice modules: reuse `SpeechService`, `SpeechInputService`, and `VoiceTextField`; expand local TTS/VoiceOver announcements for guided booking state.
- Documentation: update page specs, accessibility/voice guidelines, user stories, UI handoff/review checklist, and OpenSpec requirements to remove map-first blind-runner assumptions.
- Tests: add focused unit/UI coverage for voice-first ordering, guided booking validation, map auxiliary visibility, repeat-status copy, VoiceOver labels/hints, and unchanged API/state-machine behavior.
- APIs/backend: no new HTTP/WebSocket contract, no backend implementation, and no configurable real server address.
