## MODIFIED Requirements

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

## ADDED Requirements

### Requirement: The date picker is a real calendar
The date picker SHALL show the real year and month, page by week from Monday to Sunday, and offer both arrow buttons and a horizontal swipe to change the week. Month buttons SHALL list only months that contain a bookable date, and choosing one SHALL select that month's first bookable date. Dates before today, outside the bookable range, or without a bookable slot SHALL stay in place and SHALL NOT be selectable.

#### Scenario: Moving to the next month
- **WHEN** the bookable range covers two months and the runner chooses the second month
- **THEN** the first bookable date of that month SHALL be selected and its week SHALL be shown

#### Scenario: VoiceOver changes the date
- **WHEN** VoiceOver focuses the week
- **THEN** the week SHALL be one adjustable element whose value is the selected date
- **AND** swiping up or down SHALL move to the next or previous bookable date, changing the week when needed

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
