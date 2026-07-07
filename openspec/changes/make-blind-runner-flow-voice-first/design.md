## Context

The current SwiftUI blind-runner flow satisfies many launch requirements: phone login, profile gates, real location, AMap POI search, order creation, polling/WebSocket status updates, TTS, VoiceOver labels, cancellation confirmation, and hidden emergency UI. The remaining product gap is information architecture. Blind-runner screens still present visual map panels and dense form sections before the most useful spoken state or next action.

Project constraints remain unchanged: this repository is iOS frontend only, all real network calls use the external cloud service, AMap and real device location remain required, appointment time remains a system `DatePicker`, and no AI assistant, route navigation, real-time track sharing, backend source code, or emergency UI is introduced by this change.

## Goals / Non-Goals

**Goals:**

- Make blind-runner screens usable as a voice-first task flow where VoiceOver users encounter status and next action before map chrome.
- Keep AMap and coordinate capture intact for booking, marker display, and release validation while treating visual map inspection as auxiliary on blind-runner screens.
- Reduce booking cognitive load by replacing one long form with a guided sequence: start point, appointment time, optional needs, review and submit.
- Expand repeat-status and TTS copy so users can confirm selected location, appointment time, optional needs, permission blockers, and submit readiness.
- Update docs and tests so future UI work does not reintroduce map-first or long-form blind-runner flows.

**Non-Goals:**

- No backend API, WebSocket, database, server, or deployment changes.
- No change to canonical order statuses or transition endpoints.
- No route navigation, in-app path planning, live track sharing, geofencing, automatic phone/SMS behavior, or emergency UI.
- No natural-language time parsing and no global AI assistant.
- No volunteer workflow redesign beyond ensuring shared components and docs do not regress volunteer map behavior.

## Decisions

### 1. Keep maps, but move them behind voice-first content

Blind-runner home and booking screens should present the primary state/action first, then a concise textual location summary, then an auxiliary map affordance or secondary map region. The map should remain available for visual confirmation, AMap smoke coverage, and marker validation, but it must not be the first meaningful VoiceOver stop or the dominant blind-runner task surface.

Alternative considered: remove maps from blind-runner screens entirely. This conflicts with `AGENTS.md` and release requirements that still require AMap, current location, and order markers. Demotion preserves the release contract while improving usability.

### 2. Model booking as guided steps in the ViewModel

`BlindBookingViewModel` should own guided-step state, validation, resolved start place, appointment time, optional needs, and submit readiness. Views should render step content and navigation actions. This keeps business rules out of SwiftUI views and preserves the existing API request shape.

Alternative considered: keep the current long form and only reorder controls. That would improve the first VoiceOver pass but would not address the cognitive load of parallel optional fields.

### 3. Use textual/TTS summaries as the source of user understanding

Every guided step should have a repeatable summary. Location summaries must include whether the app is using device location, a selected AMap result, or a demo fallback. Appointment summaries must use the selected `DatePicker` value and explicitly warn when the value is invalid. Optional-needs summaries should remain short and omit empty fields.

Alternative considered: rely on VoiceOver reading visible labels. That is insufficient because repeated status must produce a coherent sentence independent of current VoiceOver focus.

### 4. Preserve field-level speech input

Existing `SpeechInputService` and `VoiceTextField` behavior remains field-level dictation. Start-place speech input may continue to auto-search AMap POIs after recognition completion. Route notes and special notes can keep microphone actions. Appointment time remains `DatePicker` only.

Alternative considered: add a conversational booking assistant. This is out of scope, raises misrecognition and safety questions, and conflicts with existing docs that exclude a global AI assistant and natural-language time parsing.

### 5. Use blind-runner-specific presentation primitives where needed

The current shared colors use system defaults. This change should introduce or reuse blind-runner-specific styling for high contrast, larger body copy, stable 64pt+ actions, and clear disabled states without forcing volunteer workbench density into the same style.

Alternative considered: rely on system dark mode. System dark mode is useful but does not guarantee the blind-runner default experience is high contrast, sparse, and one-task-per-screen.

### 6. Keep lifecycle and cancellation behavior unchanged

Order creation still calls `POST /api/orders` with the same DTO. Status screens still derive state from backend order detail, `ORDER_STATUS_CHANGED`, `VOLUNTEER_LOCATION_UPDATE`, and 5-second polling fallback. Blind-runner cancellation visibility remains limited to `PENDING_MATCH`, `PENDING_ACCEPT`, and `REMATCHING`.

Alternative considered: alter backend contracts to support guided drafts. This is unnecessary for the current frontend-only improvement and would violate repository boundaries.

## Risks / Trade-offs

- [Risk] Moving maps lower could be interpreted as violating existing "display map" wording. → Mitigation: update docs/OpenSpec to define blind-runner maps as auxiliary but still available, while volunteer maps remain operational surfaces.
- [Risk] Guided booking can add navigation friction for sighted testers. → Mitigation: keep steps shallow, expose review/submit clearly, and preserve defaults for current location and no-preference optional fields.
- [Risk] Additional TTS may become noisy. → Mitigation: ViewModels should speak on step changes, submission, errors, and explicit repeat actions, not on every field edit.
- [Risk] Collapsible/secondary map UI could hide AMap smoke failures. → Mitigation: tests should still assert that AMap-backed map content or fallback diagnostics render when the auxiliary map is opened or visible in the secondary region.
- [Risk] Docs contain older UI handoff/checklist contradictions around emergency and map-first layouts. → Mitigation: include doc cleanup tasks and OpenSpec validation before implementation is considered complete.

## Migration Plan

1. Update OpenSpec and docs to define voice-first blind-runner behavior and map-as-auxiliary semantics.
2. Refactor blind-runner home ordering so status/primary action and repeat-status precede map surfaces in visual and accessibility order.
3. Refactor booking into guided steps while keeping the same `CreateOrderRequest` and existing AMap search/reverse-geocode services.
4. Add or update tests for step validation, repeat-status copy, VoiceOver labels/hints, map auxiliary behavior, and unchanged API/status behavior.
5. Run docs validation, OpenSpec validation, unit/UI tests, and real-device AMap/cloud validation for any changed release path.

Rollback is straightforward because the backend DTO and state machine remain unchanged: the UI can return to the previous long-form booking layout without data migration if guided booking introduces blocking issues.

## Open Questions

- Should the blind-runner map be collapsed by default or visible after the repeat-status/primary action area? The spec requires it to be auxiliary and not first; implementation can choose the least risky pattern after testing VoiceOver order and AMap smoke coverage.
- Should high-contrast blind-runner styling be default for all blind-runner screens or opt-in through settings later? This change assumes default high-contrast for the affected blind-runner flow.
