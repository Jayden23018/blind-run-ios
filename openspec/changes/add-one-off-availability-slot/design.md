## Context

See proposal.md for why. The page already has a sheet editor (`VolunteerAvailabilitySlotEditor`) and an auto-saving view model. Since #357 the draft model carries `date` and shows a read-only date row for an existing one-off slot. The backend checks only that `dayOfWeek` matches `date` (`VolunteerService.validateSlot`). It does not reject past dates and has no upper limit. The contract has no upper limit either.

## Goals / Non-Goals

**Goals:**
- Create a one-off slot from the app, with a weekday the user cannot get wrong.
- Keep every existing slot intact on the whole-profile PUT.

**Non-Goals:**
- Changing the date of an existing one-off slot. The editor keeps the #357 read-only date row for that. Delete and add again instead.
- A "not free on this day" exception (backend does not support it either).
- Restyling the weekly editor or its minute pickers.

## Decisions

1. **Date choice is a `Picker` over a list of day strings, not a `DatePicker`.** Same reason the minute pickers already give: no `Date` ↔ local-day conversion, so no time-zone or DST bug at the edge. A `Picker` is also an adjustable element in VoiceOver. A compact `DatePicker` in a `Form` is a small pill well under 64pt. Alternative considered: graphical calendar `DatePicker` with `in: today...`. Rejected for the conversion risk and the much longer VoiceOver path.
2. **Window = today plus the next 29 days (30 options), named constant.** The contract gives no limit. Orders can be booked at most 7 days ahead, but a slot for a later day still matters once orders for that day come in, so 7 would be too short. 30 keeps the list short enough to swipe through with VoiceOver. A volunteer free for longer than that is better served by a weekly slot. This is reported to the backend on #566 as an iOS-side choice, not a contract rule.
3. **Day strings are computed in a fixed Gregorian UTC calendar from the `yyyy-MM-dd` of local today.** "Today" stays `VolunteerAvailableTimeSlot.todayString()` (local calendar, same as the expiry filter). Only the day arithmetic and the weekday lookup use UTC, where every day is 24 h. The weekday of a calendar date does not depend on time zone.
4. **Weekday is derived twice: when the date changes in the editor, and again when the payload is built.** The second derivation means a draft can never send a mismatched pair, even if some future code path sets `date` without the weekday. If the date string cannot be parsed, the payload falls back to the stored weekday. The backend then answers 400, which the page already shows.
5. **The new entry is a second button in the same section, not a menu on the first.** Two buttons with separate hints are discoverable in VoiceOver. A menu adds one more step and hides the second option.

## Risks / Trade-offs

- [The 30-day window is an iOS choice] → Named constant, one place to change. Mentioned in the backend reply so product can override it.
- [Default date is today, and today's 07:00 may already be past] → The slot is still valid for the backend (it only widens availability), and the volunteer sees the date before tapping 完成. Not worth a special rule.
