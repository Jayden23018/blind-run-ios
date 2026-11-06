# booking-launch-scope Specification

## Purpose
Tell blind runners before they book which cities and duty hours are open, keep them out of the booking flow while booking is closed, and handle the three launch-scope rejections from order creation with the server's own words while keeping the runner's choices.
## Requirements
### Requirement: Launch scope is optional and read per account
The client SHALL decode `launchScope` from `GET /api/config/rules` as an optional field. A missing or malformed `launchScope` SHALL NOT fail the rest of the response and SHALL be treated as "no information". The client SHALL discard the stored rules when the session ends, SHALL discard a response that arrives after the account changed, and SHALL read the rules again each time the booking entry opens.

#### Scenario: Old backend without the field
- **WHEN** the rules response has no `launchScope`
- **THEN** the other rule values SHALL still be used
- **AND** the booking flow SHALL show no launch-scope notice

#### Scenario: Account switch
- **WHEN** account A logs out and account B logs in
- **THEN** account A's launch scope SHALL NOT be shown to account B

### Requirement: Closed booking is announced before any form or voice wizard
When `acceptingOrders` is false, the booking entry SHALL show and speak `areaHint` (or a generic "not open yet" sentence when it is null) and SHALL offer only a way back to the home screen. The booking form SHALL NOT be shown and the voice booking wizard SHALL NOT start.

#### Scenario: Not accepting orders
- **WHEN** the runner opens booking and `acceptingOrders` is false
- **THEN** the screen SHALL show and speak `areaHint`
- **AND** no microphone session or `/parse` request SHALL start

### Requirement: Restrictions are shown in the step they apply to
When `areaRestricted` is true the start-point step SHALL show `areaHint`; when `dutyHoursRestricted` is true the appointment-time step SHALL show `dutyHoursHint`. When the chosen start point lies outside every open area (edges inclusive, GCJ-02) or the start time lies outside every duty window (minute precision, both ends inclusive, backend time zone), the same place SHALL say so before the server's hint. These notices SHALL NOT block submission. When a flag is false, the client SHALL say nothing about that restriction, even if the list is empty. The client SHALL NOT build or hard-code city or time-range sentences.

#### Scenario: No restriction
- **WHEN** `areaRestricted` and `dutyHoursRestricted` are both false
- **THEN** neither step SHALL show a launch-scope notice

#### Scenario: Start time on the window edge
- **WHEN** a duty window is 18:00–21:00 on that weekday and the start time is exactly 21:00
- **THEN** the time SHALL be treated as inside the window

### Requirement: Launch-scope rejections read the server message and keep the form
For `ORDER_SERVICE_NOT_OPEN`, `ORDER_OUTSIDE_OPEN_AREA`, and `APPOINTMENT_OUTSIDE_DUTY_HOURS` the client SHALL show and speak the server `message` unchanged when it is not blank, and SHALL keep every choice the runner made. `ORDER_OUTSIDE_OPEN_AREA` and `APPOINTMENT_OUTSIDE_DUTY_HOURS` SHALL leave the runner on the booking page, and `ORDER_SERVICE_NOT_OPEN` SHALL replace the booking screen with the closed notice showing that message, without suggesting a different place or time.

#### Scenario: Start point outside the open area
- **WHEN** order creation returns 422 `ORDER_OUTSIDE_OPEN_AREA`
- **THEN** the server message SHALL be shown and spoken
- **AND** the booking page SHALL stay open with the start point and time unchanged

#### Scenario: Booking closed at submit time
- **WHEN** order creation returns 422 `ORDER_SERVICE_NOT_OPEN`
- **THEN** the booking screen SHALL become the closed notice with the server message and a way back home

### Requirement: Meetup plan rejections land on the matching field
When the volunteer's meetup plan submission returns `APPOINTMENT_OUTSIDE_DUTY_HOURS`, the error SHALL appear under the time block; when it returns `ORDER_OUTSIDE_OPEN_AREA`, the error SHALL appear under the meeting-place block. Both SHALL use the server message and keep the plan form open with its content.

#### Scenario: New meeting place outside the open area
- **WHEN** the plan submission returns 422 `ORDER_OUTSIDE_OPEN_AREA`
- **THEN** the server message SHALL appear under the meeting-place block and be spoken

