## Why

The project owner walked the blind-runner booking flow on 2026-11-06 and asked for "tap once, match first, agree details on the phone" (Jayden23018/blind-run-ios#806). The current flow makes a blind runner settle the start place, an exact time and running needs in a four-step form or a voice wizard before any volunteer is contacted. Reading-screen users type at 0.66–2.11 words per minute (`docs/research/blind-input-reduction-20261106.md:77`), so every field is costly.

## What Changes

- The blind-runner home booking action opens one new booking page (mockup v4, `docs/ui/mockups/blind-match-first-20261106/`): start point (current location / favourite place), a horizontal row of the next 7 dates, a morning / afternoon / early-evening slot, an optional exact start time, and one primary action.
- The order is created as a **time-flexible** order: `plannedStartTime`/`plannedEndTime` carry the slot window, `timeFlexible = true`, and `preferredStartTime` carries the optional exact time. Running needs are not sent; the backend falls back to the profile.
- **BREAKING (behaviour)**: the home booking action no longer opens the four-step form or voice booking. The form is still embedded in the "add favourite place" path (start-place picker) until the follow-up change replaces that path and removes the old form and voice code.
- Waiting-for-match, volunteer invitation and lock-screen copy show the slot window and the preferred time, and say that the exact time is agreed on the phone.
- The volunteer meetup plan requires an exact start time on a time-flexible order and adds pace, guide dog and notes. The blind runner hears those three items before confirming.
- No new order status. Fixed partners also go through the intro call; the client keeps reading `requiresIntroCall` only.

## Capabilities

### New Capabilities
- `blind-booking-match-first`: the slot-based booking page and the time-flexible order it creates, plus how the window is shown to both sides.

### Modified Capabilities
- `blind-runner-voice-first-experience`: the single booking entry now opens the slot page; voice-booking and four-step-form requirements are removed.
- `intro-call-meetup-plan`: the plan carries running needs and requires an exact time on a time-flexible order.

## Impact

- iOS: `blindRun/BlindRunner/` (new booking page, home routing, waiting page copy, plan review rows), `blindRun/Volunteer/` (invite copy, meetup plan form), `blindRun/Core/Models/` (order and plan models).
- API: depends on Jayden23018/blind-run-backend#932 (`timeFlexible`, `preferredStartTime`, plan needs fields). The iOS change cannot be merged before #932 is on backend `main`.
- Tests: owner decision 2026-11-05 — compile only (`build-for-testing`), no device or unit test run.
