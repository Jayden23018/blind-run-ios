## ADDED Requirements

### Requirement: SOS is available to both participants only during IN_PROGRESS
The iOS app SHALL expose the order-associated SOS action to an authenticated order participant only while the canonical associated order is `IN_PROGRESS`, for both the blind and volunteer roles.

The volunteer entry was withheld until 2026-07-31 because the backend keyed the emergency event on the *triggering* user, so a volunteer press alerted that volunteer about their own SOS and escalated to the volunteer's own emergency contacts. Backend commit `a5ba523` (SOS-1) changed `event.userId` to the order's blind party and distinguishes the source with `TriggerType.VOLUNTEER_BUTTON`, so that rationale no longer holds.

#### Scenario: Blind runner is in active run
- **WHEN** the authenticated blind role owns an `IN_PROGRESS` order
- **THEN** the blind service screen SHALL expose a 64-point-or-larger SOS action with accessible label and hint

#### Scenario: Volunteer is in active run
- **WHEN** the authenticated volunteer role is the accepted participant of an `IN_PROGRESS` order
- **THEN** the volunteer service screen SHALL expose the SOS action
- **AND** the resulting event SHALL escalate to the blind runner's emergency contacts, not the volunteer's

#### Scenario: Volunteer attempts to dismiss the blind runner's emergency
- **WHEN** the authenticated volunteer tries to close or false-alarm an emergency raised for the blind runner
- **THEN** the app SHALL NOT offer that action, because in a one-to-one escort the volunteer may themselves be the threat
- **AND** the backend rejects it with 403 `EMERGENCY_VOLUNTEER_CANNOT_DISMISS`
- **AND** the only volunteer-side response the app SHALL offer is acknowledging that help is genuinely needed

#### Scenario: Order is not IN_PROGRESS
- **WHEN** canonical order status is any other value
- **THEN** both role experiences SHALL hide the *order-associated* SOS action, meaning no path may reach `POST /api/emergency/trigger`
- **AND** stale local or WebSocket state SHALL NOT expand eligibility
- **AND** a local-call affordance that sends nothing to the backend is permitted and is governed by the home-screen requirement below

### Requirement: Every trigger uses exact second confirmation
The app SHALL require second confirmation before every trigger and SHALL use exactly `是否确认进入求助状态？确认后，本次服务将标记为异常，系统会记录当前订单状态。`

#### Scenario: Participant cancels confirmation
- **WHEN** the participant chooses cancel
- **THEN** confirmation SHALL dismiss without a network request

#### Scenario: Participant confirms
- **WHEN** the participant confirms the exact approved message
- **THEN** the app SHALL revalidate role and canonical order eligibility before sending
- **AND** a second confirmation while a request is in flight SHALL NOT produce a second request

### Requirement: Trigger submits the owned order and current real GCJ-02 GPS
The iOS app SHALL submit the associated `IN_PROGRESS` order ID and a current real coordinate through the approved GCJ-02 boundary and SHALL never use a demo coordinate.

#### Scenario: Current service location is available
- **WHEN** the participant confirms and a valid current real location exists or is obtained by the bounded fresh-location request
- **THEN** one `POST /api/emergency/trigger` SHALL include `orderId`, `gpsLat`, and `gpsLng`

#### Scenario: Current service location is unavailable
- **WHEN** no valid real coordinate can be obtained within the bounded fresh-location wait
- **THEN** the app SHALL NOT send the request
- **AND** it SHALL state visibly and audibly that SOS was not submitted because the current location is unavailable, with Settings/retry guidance and the emergency number
- **AND** it SHALL never substitute Mock/demo coordinates in a cloud environment

#### Scenario: Degraded no-location submission is approved later
- **WHEN** product/safety approve the backend's location-degraded submission path
- **THEN** the behavior SHALL change through a single documented configuration constant without altering any other SOS rule

### Requirement: Trigger success creates separate emergency state
The app SHALL enter submitted/processing state only after decoding structured backend success with `success`, `eventId`, and `status`, and SHALL keep emergency state separate from `RunOrderStatus`.

#### Scenario: Structured trigger succeeds
- **WHEN** the backend returns a successful event ID and initial status
- **THEN** the coordinator SHALL retain the event keyed to authenticated user, order, and role
- **AND** the app SHALL say only that the request was recorded and is being processed

#### Scenario: Trigger fails or cannot be decoded
- **WHEN** the request fails, is rejected, or lacks the required structured success fields
- **THEN** the app SHALL visibly and audibly state that SOS was not submitted
- **AND** it SHALL offer the approved retry/Settings guidance and the emergency number

#### Scenario: Trigger is rejected by backend cooldown
- **WHEN** the backend rejects the trigger inside its cooldown window
- **THEN** the app SHALL present the remaining retry delay when the backend supplies one
- **AND** it SHALL NOT record an emergency event

#### Scenario: Emergency event is active
- **WHEN** submitted, contact-notified, or resolved event state changes
- **THEN** the canonical order status and existing finish/cancel permissions SHALL remain backend-driven and unchanged by local SOS state

### Requirement: The app never claims an emergency SMS was delivered
The app SHALL NOT display or speak that an emergency contact has received an SMS, or that family has been notified, in any state. The backend emits its contact-notified event synchronously inside the trigger transaction while the SMS is sent afterwards on an `AFTER_COMMIT` async listener, and a send failure is broadcast only to customer service and never corrected back to the blind runner, so no point in the flow proves receipt. The app SHALL substitute its own progressive-tense copy for the backend notification body whenever it renders an emergency event.

#### Scenario: HTTP trigger succeeds
- **WHEN** the backend acknowledges the trigger
- **THEN** the app SHALL say only that the request was recorded and is being processed
- **AND** it SHALL NOT show or speak that any contact received an SMS

#### Scenario: Contact-notified event arrives
- **WHEN** the backend emits its contact-notified event for the active emergency
- **THEN** the app SHALL present progressive-tense copy stating that the emergency contact is being contacted and that receipt is not yet confirmed
- **AND** it SHALL discard the backend-supplied display and TTS text for that event
- **AND** it SHALL include the emergency-number reminder

#### Scenario: Event belongs to another order
- **WHEN** an emergency event carries an order identity other than the active emergency's order
- **THEN** the app SHALL ignore it for current emergency presentation

#### Scenario: Backend later proves delivery
- **WHEN** the backend defines and emits an outcome that actually proves handset delivery, and product/compliance approve the wording
- **THEN** a delivery claim MAY be introduced only through a subsequent approved change

### Requirement: Emergency state survives navigation and is never presented unverified
Emergency state SHALL be owned at app lifetime so it survives navigation, backgrounding, and lock. Because the backend exposes no participant event-recovery endpoint or event replay, the app SHALL NOT persist emergency event metadata across process launches, and unverified retained state SHALL never be presented as current.

#### Scenario: Participant navigates away during processing
- **WHEN** a contact-notified or resolved event arrives while the service screen is absent
- **THEN** the app-lifetime coordinator SHALL retain and route the update for later presentation

#### Scenario: App relaunches after an emergency
- **WHEN** the process is relaunched
- **THEN** no prior emergency event SHALL be presented as current
- **AND** emergency state SHALL be presented again only from a fresh trigger or a live backend event

#### Scenario: Authenticated identity changes
- **WHEN** logout, account deletion, session expiration, role switch, or another user sign-in occurs
- **THEN** prior emergency state SHALL be cleared and SHALL NOT be presented under the new session

### Requirement: The blind-runner home exposes a persistent help affordance whose mode follows order status
The blind-runner home SHALL present a persistent bottom help action, reachable without scrolling and also by the VoiceOver Magic Tap gesture. Its mode SHALL be derived from canonical order status and SHALL NOT be user-selectable.

While the owned order is `IN_PROGRESS` it SHALL behave exactly as the order-associated SOS defined above, including the verbatim second confirmation and the fresh-GCJ-02 gate. In every other state it SHALL degrade to a purely local telephone call, SHALL NOT call any emergency endpoint, and its copy SHALL state that the app is not sending a request on the user's behalf — a blind user who presses it hears only a dialer, and silence about that would let them believe help had been summoned.

#### Scenario: Owned order is IN_PROGRESS
- **WHEN** the blind participant activates the home help action for an owned `IN_PROGRESS` order
- **THEN** the app SHALL run the order-associated SOS path with the verbatim confirmation and the fresh-coordinate gate

#### Scenario: No active order or a non-IN_PROGRESS order
- **WHEN** the blind participant activates the home help action in any other state
- **THEN** the app SHALL NOT issue any emergency request
- **AND** it SHALL offer a choice between the sole primary emergency contact, when exactly one exists, and the emergency number
- **AND** the presented copy SHALL state that the app is not sending a request on the user's behalf

#### Scenario: Primary emergency contact is absent or ambiguous
- **WHEN** zero or more than one primary emergency contact exists
- **THEN** the app SHALL offer only the emergency number and SHALL say why the contact option is unavailable

#### Scenario: Help action is reached by gesture
- **WHEN** the blind participant performs the VoiceOver Magic Tap on the home screen
- **THEN** the app SHALL activate the same mode-appropriate help action as the visible control

### Requirement: SOS presentation is accessible and responsibility safe
Eligibility, locating, confirmation, submission, processing, failure, cooldown, contact-notified, and resolved states SHALL have equivalent visible, VoiceOver, and TTS presentation without promising rescue beyond backend-confirmed facts.

#### Scenario: Blind runner repeats current state
- **WHEN** the blind runner invokes repeat-current-status during an active emergency event
- **THEN** the app SHALL speak canonical order status followed by the latest authoritative emergency state and next action

#### Scenario: Trigger attempt reaches any outcome
- **WHEN** locating, submitting, unsent, failure, cooldown, contact-notified, or resolved state is reached
- **THEN** the app SHALL both show and speak that state
- **AND** copy for every state that does not prove help is under way SHALL include the emergency number
