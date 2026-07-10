## ADDED Requirements

### Requirement: Independent SOS is reachable for authenticated blind users
The iOS app SHALL provide an always-reachable SOS action for every authenticated user whose active role is `BLIND`, regardless of profile, identity, emergency-contact, order, or location completion.

#### Scenario: Blind user has no active order
- **WHEN** an authenticated blind-role user is on a blind onboarding or home flow without an eligible order
- **THEN** the app SHALL expose the SOS action with a minimum 64-point target and accessible label/hint

#### Scenario: Non-blind role is active
- **WHEN** the active role is `VOLUNTEER`
- **THEN** the app SHALL NOT expose an independent SOS trigger
- **AND** the volunteer MAY receive an associated emergency alert through the response flow

### Requirement: Every SOS trigger requires exact second confirmation
The app SHALL require second confirmation before every `POST /api/emergency/trigger` and SHALL use the exact confirmation text required by the current approved project rule until that rule is explicitly changed.

#### Scenario: User cancels confirmation
- **WHEN** the blind user opens SOS confirmation and chooses cancel
- **THEN** the app SHALL dismiss confirmation without making a network request

#### Scenario: User confirms SOS
- **WHEN** the blind user confirms the exact approved message
- **THEN** the app SHALL disable duplicate submission and send one trigger request

### Requirement: SOS request fields are optional and context aware
The app SHALL omit `orderId`, `gpsLat`, and `gpsLng` when their eligible values are unavailable and SHALL NOT block SOS because an optional field is missing.

#### Scenario: Eligible active order and location exist
- **WHEN** the blind user confirms SOS with an order in `DRIVER_EN_ROUTE`, `DRIVER_ARRIVED`, or `IN_PROGRESS` and authorized current device location
- **THEN** the request SHALL include that order ID and current latitude/longitude

#### Scenario: No eligible active order exists
- **WHEN** the blind user confirms SOS without an eligible service order
- **THEN** the request SHALL omit `orderId`
- **AND** the backend event SHALL remain independent of order lifecycle

#### Scenario: Current location is unavailable
- **WHEN** permission is denied or no current device coordinate exists
- **THEN** the request SHALL omit both GPS fields and proceed
- **AND** the app SHALL state that precise device location was not included without exposing raw coordinates

### Requirement: Trigger success is represented as an emergency event
The app SHALL treat a trigger as submitted only after decoding a successful response containing `success`, `eventId`, and `status`, and SHALL keep emergency state separate from `RunOrderStatus`.

#### Scenario: Trigger returns pending event
- **WHEN** the backend returns `{success:true,eventId,status:"PENDING"}`
- **THEN** the app SHALL retain the event ID, present pending state, and announce that the event was recorded and is being processed
- **AND** it SHALL NOT claim that a rescuer or emergency service has been dispatched

#### Scenario: Trigger is associated with an order
- **WHEN** a successful emergency event includes an eligible order ID
- **THEN** the existing order SHALL continue to use its canonical lifecycle status
- **AND** order polling/WebSocket handling SHALL continue normally

### Requirement: Unsent and cooldown states are explicit
The app SHALL distinguish network/server failure from successful submission and SHALL honor backend cooldown retry semantics.

#### Scenario: Trigger cannot be sent
- **WHEN** the trigger request fails without a structured successful response
- **THEN** the app SHALL state visibly and audibly that SOS was not sent
- **AND** it SHALL offer retry and approved offline safety guidance

#### Scenario: Backend cooldown prevents duplicate event
- **WHEN** the backend returns the documented cooldown response
- **THEN** the app SHALL preserve the existing event state
- **AND** the SOS action SHALL show the authoritative retry interval without creating a local duplicate

### Requirement: Emergency follow-up is event-ID driven and recoverable
The app SHALL route emergency follow-up by event ID and SHALL restore current event status after navigation, WebSocket reconnection, or app relaunch through the documented recovery contract. Persisted recovery metadata SHALL be scoped to the authenticated user and SHALL NOT survive logout, account deletion, session expiration, or a change to another user.

#### Scenario: Emergency contact notification arrives
- **WHEN** `EMERGENCY_CONTACT_NOTIFIED` arrives for the current event ID
- **THEN** the app SHALL update and announce contact-notified state
- **AND** it SHALL not present that state for a different event

#### Scenario: Event is resolved
- **WHEN** a documented resolved event arrives or recovery reports resolution
- **THEN** the app SHALL present the authoritative resolved outcome
- **AND** it SHALL stop presenting the event as pending

#### Scenario: App relaunches with pending event metadata
- **WHEN** the app restores a locally retained event ID
- **THEN** it SHALL query or otherwise use the documented backend recovery mechanism before presenting a current status as authoritative

#### Scenario: Authenticated account changes
- **WHEN** the current user logs out, deletes the account, loses the authenticated session, or another user signs in on the device
- **THEN** the app SHALL clear the prior user's retained emergency metadata and in-memory event state
- **AND** it SHALL NOT query or present the prior user's event under the new session

### Requirement: Associated volunteers can respond safely
The volunteer app SHALL present a high-priority associated emergency alert and SHALL require confirmation before sending `NEED_HELP` or `FALSE_ALARM` through the documented query-parameter endpoint.

#### Scenario: Volunteer confirms help is needed
- **WHEN** an authorized associated volunteer confirms `NEED_HELP` for the event
- **THEN** the app SHALL call `PUT /api/emergency/{eventId}/volunteer-response?action=NEED_HELP`
- **AND** it SHALL present the backend-confirmed result without claiming to run escalation locally

#### Scenario: Volunteer confirms false alarm
- **WHEN** an authorized associated volunteer confirms `FALSE_ALARM`
- **THEN** the app SHALL call `PUT /api/emergency/{eventId}/volunteer-response?action=FALSE_ALARM`
- **AND** it SHALL require a second confirmation because this response can change safety escalation

#### Scenario: Volunteer alert contains location data
- **WHEN** the emergency alert contains GPS fields
- **THEN** the app SHALL NOT display raw coordinates, a blind-user live marker, direction, route, or track
- **AND** it SHALL use only approved backend-provided safety/location text

### Requirement: SOS presentation is accessible and responsibility safe
SOS entry, confirmation, submission, pending, cooldown, failure, escalation, contact-notified, and resolved states SHALL have equivalent visible, VoiceOver, and TTS presentation and SHALL not overpromise rescue.

#### Scenario: Blind user repeats SOS status
- **WHEN** the user invokes repeat-current-status while an emergency event is active
- **THEN** the app SHALL speak the latest authoritative emergency state, location-submission state, and next safe action

#### Scenario: Safety copy is reviewed
- **WHEN** release-facing SOS copy is inspected
- **THEN** it SHALL distinguish event recording from emergency-service dispatch
- **AND** it SHALL use only product/compliance-approved offline and escalation language
