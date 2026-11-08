## MODIFIED Requirements

### Requirement: Launch-scope rejections read the server message and keep the form
For `ORDER_SERVICE_NOT_OPEN`, `ORDER_OUTSIDE_OPEN_AREA`, and `APPOINTMENT_OUTSIDE_DUTY_HOURS` the client SHALL show and speak the server `message` unchanged when it is not blank, and SHALL keep every choice the runner made. `ORDER_OUTSIDE_OPEN_AREA` and `APPOINTMENT_OUTSIDE_DUTY_HOURS` SHALL leave the runner on the booking page, and `ORDER_SERVICE_NOT_OPEN` SHALL replace the booking screen with the closed notice showing that message, without suggesting a different place or time.

#### Scenario: Start point outside the open area
- **WHEN** order creation returns 422 `ORDER_OUTSIDE_OPEN_AREA`
- **THEN** the server message SHALL be shown and spoken
- **AND** the booking page SHALL stay open with the start point and time unchanged

#### Scenario: Booking closed at submit time
- **WHEN** order creation returns 422 `ORDER_SERVICE_NOT_OPEN`
- **THEN** the booking screen SHALL become the closed notice with the server message and a way back home
