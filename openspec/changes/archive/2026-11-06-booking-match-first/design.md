## Context

See proposal.md. Backend facts (origin/main, 2026-11-06): `RunOrder.plannedStartTime` is NOT NULL and six dispatch paths read it, so an order cannot be created without a time. The meetup plan (`PUT /api/orders/{id}/intro-call/plan`) and the runner's versioned confirmation (`POST .../intro-call/decision`) already exist. Backend contract changes are tracked in Jayden23018/blind-run-backend#932.

## Goals / Non-Goals

**Goals:** one booking page that matches mockup v4; a time-flexible order; window-aware copy on both sides; plan carries needs.

**Non-Goals:** deleting the old form and voice wizard code (follow-up change); a designated-partner booking (no backend support); text chat (calls stay on the masked-number phone).

## Decisions

- **Window instead of "no time".** The slot window is a legal order time (≤300 min, outside 22:00–05:00, ≥30 min ahead), so every backend check stays valid. Alternative "time pending" (null time) was rejected: it breaks six dispatch paths and the NOT NULL column.
- **Reuse `BlindBookingViewModel` for location, gates and submit.** The new page owns only date / slot / time selection and asks the view model to build a time-flexible request. This keeps the launch-scope, precise-location and track-consent gates and the error mapping unchanged. Alternative (new view model) duplicates the start-location logic.
- **Slot table is a client constant** (`06:00–11:00`, `13:00–17:00`, `17:00–21:00`), clipped by the minimum lead time; dates come from the backend's 7-day horizon. A slot today is offered only if ≥60 min remain after clipping.
- **Optional exact time = `preferredStartTime`**, not a narrowed window, so the volunteer can still move the run inside the slot after the call.
- **Client never decides direct accept.** Fixed partners also call because the backend sets `requiresIntroCall` for time-flexible orders; the client keeps its existing rule.
- **Visuals follow mockup v4 measurements**, with two owner-approved deviations: neutral stroke `#7C7C80` on unselected options and a 64 pt hit area.

## Risks / Trade-offs

- [Backend #932 not merged] → iOS PR stays draft; new request fields are optional and decoding treats missing keys as "not flexible".
- [Horizontal date row hides dates for large-text users] → owner accepted (v4); VoiceOver still reads all 7 with position.
- [Old form and voice code become unreachable] → follow-up change deletes them with their tests and corpus gates.
