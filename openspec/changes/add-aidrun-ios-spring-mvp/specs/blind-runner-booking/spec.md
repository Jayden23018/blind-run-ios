## ADDED Requirements

### Requirement: Blind runner profile is required before booking

The system MUST require blind runners to provide nickname, emergency contact name, and emergency contact phone before creating an appointment order.

#### Scenario: Missing profile blocks booking
- **WHEN** a blind runner without a complete profile creates an order
- **THEN** the backend returns `PROFILE_INCOMPLETE`

### Requirement: Blind runner can create appointment order

The system MUST allow a blind runner to create one appointment-style run order with required start location and appointment time.

#### Scenario: Valid booking
- **WHEN** a blind runner submits start location and appointment time at least 30 minutes in the future
- **THEN** the backend creates a `matching` order

### Requirement: Appointment time must be at least 30 minutes later

The system MUST reject bookings whose appointment time is less than 30 minutes from the current time.

#### Scenario: Appointment too soon
- **WHEN** a blind runner submits an appointment time less than 30 minutes from now
- **THEN** the backend returns `APPOINTMENT_TOO_SOON`

### Requirement: Optional route fields do not trigger route navigation

The system MUST accept destination or route text, estimated duration, estimated distance, pace preference, same-gender preference, and remarks as optional metadata only.

#### Scenario: Optional route omitted
- **WHEN** a blind runner creates an order with only start location and valid appointment time
- **THEN** the order is created without route navigation or automatic route planning
