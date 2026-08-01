## ADDED Requirements

### Requirement: API contract defines order-associated SOS authorization
The canonical API contract MUST define who may call `POST /api/emergency/trigger` for an `IN_PROGRESS` order and MUST define GCJ-02 request fields. Volunteer-token triggers MUST NOT be documented as usable until the backend escalates by order participant instead of by triggering user.

#### Scenario: Blind participant triggers
- **WHEN** the blind participant submits the owned `IN_PROGRESS` order ID and valid current GCJ-02 GPS
- **THEN** the backend accepts or rejects it using the documented structured contract

#### Scenario: Volunteer participant triggers
- **WHEN** the accepted volunteer submits the same order association
- **THEN** the contract MUST state that the resulting event is keyed to the volunteer, alerts that same volunteer, does not notify the blind runner, and escalates to the volunteer's own emergency contacts
- **AND** iOS MUST NOT enable a volunteer trigger until that behavior changes

#### Scenario: User is not an eligible participant
- **WHEN** the token is not a participant or the order is not `IN_PROGRESS`
- **THEN** the backend rejects the request with a stable unified error

### Requirement: Trigger result and errors are structured
The canonical API contract MUST define successful `success`, `eventId`, and `status` fields plus validation, authorization, duplicate/cooldown, and business-error schemas.

#### Scenario: Trigger is recorded
- **WHEN** the backend records an emergency event
- **THEN** it returns the event identity and initial status without changing canonical order status

#### Scenario: Trigger is inside cooldown
- **WHEN** the same participant/order retriggers inside the backend window
- **THEN** the response contains stable code and machine-readable retry/existing-event semantics

### Requirement: Both participants receive typed emergency follow-up
The canonical WebSocket/recovery contract MUST define event-ID/order-ID-keyed submitted, contact-notified, and resolved outcomes for the initiating participant and any associated participant expected to present state.

#### Scenario: Emergency contact notification completes
- **WHEN** backend SMS processing reaches the documented contact-notified outcome
- **THEN** the appropriate blind and volunteer clients receive or recover a typed event with safe display/TTS text, timestamp, priority, event ID, and order ID

#### Scenario: Event is resolved
- **WHEN** backend processing resolves or closes the event
- **THEN** both relevant clients can receive or recover the authoritative result

### Requirement: SMS notification semantics are explicit
The contract MUST state that its contact-notified event is emitted before the SMS is attempted and therefore proves nothing about delivery, and MUST document the message's real envelope, which today is an `APP_NOTIFICATION` carrying an `eventType` and no event or order ID.

#### Scenario: iOS receives contact-notified event
- **WHEN** the backend emits the event
- **THEN** the documented semantics MUST make clear that receipt is unproven
- **AND** iOS MUST present progressive-tense copy rather than any delivery claim

#### Scenario: SMS delivery fails
- **WHEN** the emergency SMS fails to send
- **THEN** the contract MUST state whether the triggering user is informed
- **AND** while no correction reaches that user, iOS MUST assume the worst case in its copy

### Requirement: Emergency event recovery is participant authorized
The external contract MUST provide an authenticated mechanism for an associated participant to recover the authoritative state of an owned event after reconnect or relaunch. While no such mechanism exists, iOS MUST NOT persist emergency state across launches.

#### Scenario: Participant recovers owned event
- **WHEN** iOS requests state for an event associated with the authenticated participant/order
- **THEN** the backend returns current safe status and notification fields

#### Scenario: User requests another event
- **WHEN** an unrelated user requests recovery
- **THEN** the backend rejects access with a unified authorization error
