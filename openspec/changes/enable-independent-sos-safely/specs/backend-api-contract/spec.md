## ADDED Requirements

### Requirement: API contract defines dual-role order-associated SOS
The canonical API contract MUST authorize both associated `BLIND` and `VOLUNTEER` tokens to call `POST /api/emergency/trigger` for their `IN_PROGRESS` order and MUST define GCJ-02 request fields.

#### Scenario: Blind participant triggers
- **WHEN** the blind participant submits the owned `IN_PROGRESS` order ID and valid current GCJ-02 GPS
- **THEN** the backend accepts or rejects it using the documented structured contract

#### Scenario: Volunteer participant triggers
- **WHEN** the accepted volunteer submits the same order association and valid current GCJ-02 GPS
- **THEN** the backend applies equivalent authorization/event semantics

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
The contract MUST state whether contact-notified means queued, provider-accepted, delivered to handset, or another precisely defined state so iOS copy does not overpromise.

#### Scenario: iOS receives contact-notified event
- **WHEN** the backend emits the event
- **THEN** the documented semantics are sufficient to decide whether “联系人已收到短信” is truthful and approved

### Requirement: Emergency event recovery is participant authorized
The external contract MUST provide an authenticated mechanism for either associated participant to recover the authoritative state of an owned event after reconnect or relaunch.

#### Scenario: Participant recovers owned event
- **WHEN** iOS requests state for an event associated with the authenticated participant/order
- **THEN** the backend returns current safe status and notification fields

#### Scenario: User requests another event
- **WHEN** an unrelated user requests recovery
- **THEN** the backend rejects access with a unified authorization error
