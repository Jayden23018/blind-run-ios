## ADDED Requirements

### Requirement: API contract defines independent SOS trigger
The canonical API contract MUST define `POST /api/emergency/trigger` for a blind JWT with optional `orderId`, `gpsLat`, and `gpsLng` fields and a structured success response containing `success`, `eventId`, and `status`.

#### Scenario: Independent SOS is accepted
- **WHEN** a blind user sends a trigger without `orderId`
- **THEN** the backend records an independent event and returns its event ID and initial status

#### Scenario: Eligible order SOS is accepted
- **WHEN** a blind user sends an owned eligible active order ID
- **THEN** the backend associates the event without changing canonical order status

#### Scenario: GPS fields are omitted
- **WHEN** both GPS fields are absent
- **THEN** the backend accepts the request and applies its documented location-degradation behavior

### Requirement: API contract defines SOS cooldown and errors
The canonical API contract MUST document authentication, order-eligibility, validation, cooldown, duplicate, and network-independent business responses with a machine-readable retry interval where applicable.

#### Scenario: Trigger is inside cooldown
- **WHEN** the user retriggers inside the backend cooldown window
- **THEN** the backend returns a stable cooldown response with retry semantics
- **AND** it documents whether the existing active event ID is returned

### Requirement: API contract defines emergency event recovery
The external contract MUST provide a documented authenticated mechanism for a blind user to recover the authoritative state of a retained emergency event after reconnect or relaunch.

#### Scenario: Pending event is recovered
- **WHEN** iOS provides an owned pending event ID after relaunch
- **THEN** the backend returns the current event state and user-safe status fields

#### Scenario: User requests another event
- **WHEN** the event ID is not owned by the authenticated blind user
- **THEN** the backend rejects access with a unified authorization error

### Requirement: API contract defines volunteer emergency response
The canonical API and WebSocket contracts MUST define the associated volunteer alert and `PUT /api/emergency/{eventId}/volunteer-response?action=NEED_HELP|FALSE_ALARM` behavior, authorization, timeout, idempotency, and result schemas.

#### Scenario: Associated volunteer responds in time
- **WHEN** the alerted associated volunteer submits one documented action before timeout
- **THEN** the backend records the response and returns a structured event result

#### Scenario: Unauthorized volunteer responds
- **WHEN** a volunteer not associated with the event submits a response
- **THEN** the backend rejects it with a unified authorization error

#### Scenario: Volunteer does not respond
- **WHEN** the response timeout expires
- **THEN** backend-owned escalation proceeds without requiring the iOS app to run a scheduler

### Requirement: WebSocket contract defines emergency follow-up states
The WebSocket contract MUST document event-ID-keyed messages for the blind runner and associated volunteer, including pending, contact-notified, escalated, resolved, and false-alarm outcomes that iOS is expected to present.

#### Scenario: Follow-up state changes
- **WHEN** backend emergency processing changes a user-visible event state
- **THEN** the appropriate role WebSocket emits a typed event containing event ID, state, priority, timestamp, and safe display/TTS text
