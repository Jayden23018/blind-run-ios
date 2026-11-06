## Purpose

Let a blind runner start matching with a volunteer by choosing only a date and a coarse time slot, and leave the exact time, meeting point and running needs to the intro call and the volunteer's meetup plan.

## ADDED Requirements

### Requirement: Booking asks for a date and a slot, not an exact time
The booking page SHALL let the blind runner choose a start point, one of the next 7 dates, and one of three slots (morning 06:00–11:00, afternoon 13:00–17:00, early evening 17:00–21:00). An exact start time SHALL be optional.

#### Scenario: Default selection is ready to submit
- **WHEN** the page opens
- **THEN** the current location, the earliest date that still has a bookable slot, and that slot SHALL already be selected
- **AND** activating the primary action SHALL create the order without any further input

#### Scenario: Slots that are too late today are not selectable
- **WHEN** a slot today has less than 60 minutes left after the minimum booking lead time
- **THEN** that slot SHALL be shown as unavailable and SHALL NOT be selectable
- **AND** a date with no bookable slot SHALL be shown as unavailable

#### Scenario: Exact time is optional and limited to the slot
- **WHEN** the runner selects a slot
- **THEN** the page SHALL offer start times every 30 minutes inside the slot that leave at least 30 minutes of running before the slot ends and respect the minimum lead time
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
