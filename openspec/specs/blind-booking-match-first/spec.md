# blind-booking-match-first Specification

## Purpose
Let a blind runner start matching with a volunteer by choosing only a date and a coarse time slot, and leave the exact time, meeting point and running needs to the intro call and the volunteer's meetup plan.
## Requirements
### Requirement: Booking asks for a date and a slot, not an exact time
The booking page SHALL let the blind runner choose a start point, a date inside the bookable range, and one of three slots (morning 06:00–11:00, afternoon 13:00–17:00, early evening 17:00–21:00). The bookable range SHALL end at now plus `maxLeadDays` days, read from `GET /api/config/rules`; when the field is missing or not positive the app SHALL use 7. An exact start time SHALL be optional.

#### Scenario: Default selection is ready to submit
- **WHEN** the page opens
- **THEN** the home screen's default start place (or the current location when none is set), the earliest date that still has a bookable slot, and that slot SHALL already be selected
- **AND** activating the primary action SHALL create the order without any further input

#### Scenario: Slots that are too late today are not selectable
- **WHEN** a slot today has less than 60 minutes left after the minimum booking lead time
- **THEN** that slot SHALL be shown as unavailable and SHALL NOT be selectable
- **AND** a date with no bookable slot SHALL be shown as unavailable

#### Scenario: Exact time is optional and limited to the slot
- **WHEN** the runner selects a slot
- **THEN** the page SHALL offer start times every 30 minutes inside the slot that leave at least 30 minutes of running before the slot ends, respect the minimum lead time, and are not later than the latest bookable start
- **AND** selecting the same time again SHALL clear it

### Requirement: The order is created as a time-flexible window
The app SHALL create the order with the chosen slot as `plannedStartTime`–`plannedEndTime`, `timeFlexible = true`, and the optional exact time as `preferredStartTime`. It SHALL NOT send pace or guide-dog values from this page.

#### Scenario: Submit without an exact time
- **WHEN** the runner submits with no exact time selected
- **THEN** the request SHALL carry the slot window, `timeFlexible = true`, and no `preferredStartTime`

### Requirement: Both sides see the window, not a fake exact time
Wherever a time-flexible order shows its time before a meetup plan is confirmed, the app SHALL show the window and SHALL say that the exact time is agreed on the phone. When a preferred time exists it SHALL be shown as "about HH:mm".

#### Scenario: Waiting for a match
- **WHEN** the runner's time-flexible order is waiting for a match
- **THEN** the waiting page SHALL state the window and the preferred time, and that a phone call comes first

#### Scenario: Volunteer invitation
- **WHEN** a volunteer sees an invitation for a time-flexible order
- **THEN** the invitation SHALL state the window and the preferred time
- **AND** whether a direct accept is offered SHALL still follow `requiresIntroCall` only

### Requirement: Unselected controls keep a visible boundary
Unselected options on the booking page SHALL have a border of at least 3:1 contrast against the page, and every option SHALL keep a hit area at least 64 pt tall.

#### Scenario: Low-vision runner scans the page
- **WHEN** the page renders in light or dark appearance
- **THEN** every unselected option's border SHALL use the neutral button stroke colour

### Requirement: The date picker is a real calendar
The date picker SHALL show one horizontally scrollable row of dates from today to the last bookable date, with no week paging. A month label SHALL appear above the first date in the row and above the first day of each later month, and SHALL scroll with the dates. The month of the selected date SHALL be shown in bold. Each date SHALL show its weekday, and today SHALL say 今天. Dates without a bookable slot SHALL stay in place and SHALL NOT be selectable.

#### Scenario: Scrolling into the next month
- **WHEN** the bookable range covers two months and the runner scrolls to the end of the row
- **THEN** the second month's label SHALL appear above its first day
- **AND** selecting a date in that month SHALL make its label bold

#### Scenario: VoiceOver changes the date
- **WHEN** VoiceOver focuses the date row
- **THEN** the row SHALL be one adjustable element whose value is the selected date
- **AND** swiping up or down SHALL move to the next or previous bookable date and scroll it into view

### Requirement: Slots follow the backend duty hours
When `launchScope.dutyHoursRestricted` is true and the duty windows can be read, each slot SHALL be limited to the part that falls inside a duty window. A slot with less than 60 minutes inside duty hours SHALL be unavailable and SHALL say it is outside duty hours. The page SHALL show the backend's `dutyHoursHint` unchanged. When the windows cannot be read, the app SHALL NOT limit the slots and the order response remains the final decision.

#### Scenario: Weekday evening duty hours
- **WHEN** duty hours are Monday to Friday 18:00–21:00
- **THEN** on a weekday the morning and afternoon slots SHALL be unavailable and the evening slot SHALL be 18:00–21:00
- **AND** Saturday and Sunday SHALL be shown as unavailable dates

### Requirement: The start point uses the same place library as the default start place page
The start point choice SHALL show the current location, every saved place, and an add button as the same coloured circles used on the default start place page. Choosing one SHALL apply to this order only and SHALL NOT change the default start place. At accessibility text sizes the circles SHALL become a list.

#### Scenario: Adding a place while booking
- **WHEN** the runner adds a saved place from the booking page
- **THEN** the app SHALL return to the booking page with the new place selected

