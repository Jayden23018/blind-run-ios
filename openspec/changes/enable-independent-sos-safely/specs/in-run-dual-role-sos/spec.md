## ADDED Requirements

### Requirement: SOS is available to both participants only during IN_PROGRESS
The iOS app SHALL expose the order-associated SOS action to the authenticated blind runner and volunteer only while their canonical associated order is `IN_PROGRESS`.

#### Scenario: Blind runner is in active run
- **WHEN** the authenticated blind role owns an `IN_PROGRESS` order
- **THEN** the blind service screen SHALL expose a 64-point-or-larger SOS action with accessible label and hint

#### Scenario: Volunteer is in active run
- **WHEN** the authenticated volunteer role is the accepted participant of an `IN_PROGRESS` order
- **THEN** the volunteer service screen SHALL expose the same SOS capability

#### Scenario: Order is not IN_PROGRESS
- **WHEN** canonical order status is any other value
- **THEN** both role experiences SHALL hide the SOS action
- **AND** stale local or WebSocket state SHALL NOT expand eligibility

### Requirement: Every trigger uses exact second confirmation
The app SHALL require second confirmation before every trigger and SHALL use exactly `是否确认进入求助状态？确认后，本次服务将标记为异常，系统会记录当前订单状态。` for both roles.

#### Scenario: Participant cancels confirmation
- **WHEN** the participant chooses cancel
- **THEN** confirmation SHALL dismiss without a network request

#### Scenario: Participant confirms
- **WHEN** the participant confirms the exact approved message
- **THEN** the app SHALL revalidate role/order eligibility and prevent duplicate submission

### Requirement: Trigger submits the owned order and current real GCJ-02 GPS
The iOS app SHALL submit the associated `IN_PROGRESS` order ID and a current real coordinate through the approved GCJ-02 boundary and SHALL never use a demo coordinate.

#### Scenario: Current service location is available
- **WHEN** the participant confirms and a valid current real location exists or is obtained by the bounded fresh-location request
- **THEN** one `POST /api/emergency/trigger` SHALL include `orderId`, `gpsLat`, and `gpsLng`

#### Scenario: Current service location is unavailable
- **WHEN** no valid real coordinate can be obtained under the approved policy
- **THEN** the app SHALL follow the product/safety-approved no-location behavior
- **AND** it SHALL never claim submission unless the backend accepts a request
- **AND** it SHALL never substitute Mock/demo coordinates in a cloud environment

### Requirement: Trigger success creates separate emergency state
The app SHALL enter submitted/processing state only after decoding structured backend success with `success`, `eventId`, and `status`, and SHALL keep emergency state separate from `RunOrderStatus`.

#### Scenario: Structured trigger succeeds
- **WHEN** the backend returns a successful event ID and initial status
- **THEN** the coordinator SHALL retain the event keyed to authenticated user, order, and role
- **AND** the app SHALL say only that the request was recorded and is being processed

#### Scenario: Trigger fails or cannot be decoded
- **WHEN** the request fails or lacks the required structured success fields
- **THEN** the app SHALL visibly and audibly state that SOS was not submitted
- **AND** it SHALL offer the approved retry/Settings guidance

#### Scenario: Emergency event is active
- **WHEN** submitted, contact-notified, or resolved event state changes
- **THEN** the canonical order status and existing finish/cancel permissions SHALL remain backend-driven and unchanged by local SOS state

### Requirement: SMS receipt copy requires a matching backend notification
The app SHALL display and speak “联系人已收到短信” only after a backend contact-notified event matches the active emergency event ID, order ID, authenticated participant, and approved SMS semantics.

#### Scenario: HTTP trigger succeeds without contact event
- **WHEN** trigger acknowledgement is successful but no matching contact-notified event has arrived
- **THEN** the app SHALL remain in submitted/processing state
- **AND** it SHALL NOT show or speak that the contact received an SMS

#### Scenario: Matching contact notification arrives
- **WHEN** the documented backend event confirms the approved SMS outcome for the current event/order
- **THEN** the app SHALL update visible, VoiceOver, TTS, and repeat-status presentation to “联系人已收到短信”

#### Scenario: Unrelated or stale contact notification arrives
- **WHEN** the event/order/user identity does not match the current emergency state
- **THEN** the app SHALL ignore it for current SMS presentation

### Requirement: Emergency state survives navigation and is safely recoverable
Emergency state SHALL be routed independently of screen lifetime and any retained recovery metadata SHALL be user/order scoped and backend-reconciled after reconnect or relaunch.

#### Scenario: Participant navigates away during processing
- **WHEN** a matching contact-notified or resolved event arrives while the service screen is absent
- **THEN** the app-lifetime coordinator SHALL retain/route the update for later presentation

#### Scenario: App relaunches with retained event ID
- **WHEN** local metadata identifies a prior pending event
- **THEN** the app SHALL recover authoritative backend state before presenting it as current

#### Scenario: Authenticated identity changes
- **WHEN** logout, account deletion, session expiration, or another user sign-in occurs
- **THEN** prior emergency state and metadata SHALL be cleared and SHALL NOT be queried or presented under the new session

### Requirement: SOS presentation is accessible and responsibility safe
Eligibility, locating, confirmation, submission, processing, failure, cooldown, contact-notified, and resolved states SHALL have equivalent visible, VoiceOver, and TTS presentation without promising rescue beyond backend-confirmed facts.

#### Scenario: Blind runner repeats current state
- **WHEN** the blind runner invokes repeat-current-status during an active emergency event
- **THEN** the app SHALL speak canonical order status followed by the latest authoritative emergency state and next action
