## Context

HANDOFF §7 is the acceptance list. The first check ("labels match the prototype's `data-vo`, wording may change, information may not be lost") is judged against `run-record-handoff/prototype.html`. The screens are `RunRecordHistoryView` (both roles), `VolunteerRunRecordView`, `RunnerRunRecordView`.

## Decisions

- **Legend inside `RunRecordRouteMap`**, not on each page, so both details get it from one place. It is drawn only when the route is actually coloured by pace (`RunPaceScale` exists); with no samples the route is one colour and a legend would be wrong. It is `accessibilityHidden`: VoiceOver users get the meaning from the description, and the map is already outside the tree.
- **Navigation title via a principal toolbar item** carrying a spoken label. `navigationTitle` has no way to give a separate spoken string.
- **Masked-name and apostrophe checks are UI-test sweeps over every element's label and value**, not per-element assertions. A new element that leaks `*` or `6'15"` fails without anyone thinking to add an assertion for it.
- **Out of scope**: the P1 high-contrast runner map, voice reply, map replay. Screen-wide problems found elsewhere in the app go to separate issues.

## Risks

- VoiceOver reading order and pronunciation (for example how "06:35" is read) can only be checked by ear on a device.
- Increase Contrast cannot be switched on from XCUITest, so it has to be set by hand in Settings for the screenshot run.
