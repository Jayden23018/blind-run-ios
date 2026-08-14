## MODIFIED Requirements

### Requirement: Blind runner state updates remain status driven
The blind-runner order experience SHALL remain driven by canonical order status while presenting the associated volunteer's fresh live location during eligible states and the completed run summary after `COMPLETED`. While the order is still waiting to be matched, the experience SHALL also offer the blind runner a way to extend the waiting window before the backend abandons the order.

#### Scenario: Volunteer is travelling, arrived, or running
- **WHEN** the order is `DRIVER_EN_ROUTE`, `DRIVER_ARRIVED`, or `IN_PROGRESS`
- **THEN** the blind-runner flow MAY present the associated volunteer's fresh map marker from routed WebSocket data
- **AND** it SHALL keep status, primary action, and repeat-status information accessible ahead of auxiliary map inspection

#### Scenario: Order completes
- **WHEN** canonical order detail becomes `COMPLETED`
- **THEN** the blind-runner completion flow SHALL offer the track summary with blind route, distance, duration, and pace

#### Scenario: Volunteer accepts dispatch
- **WHEN** the coordinator routes `ORDER_STATUS_CHANGED` or polling returns `PENDING_ACCEPT`
- **THEN** the app SHALL refresh and show the canonical "待出发" state
- **AND** TTS SHALL use local order-detail copy rather than duplicate lifecycle template speech

#### Scenario: No volunteer is available
- **WHEN** WebSocket or polling returns `NO_VOLUNTEER`
- **THEN** the app SHALL show and announce a no-volunteer terminal state
- **AND** the app SHALL NOT offer to extend the waiting window from this state, because the backend treats it as terminal and both extension endpoints reject it

#### Scenario: Waiting order offers to keep waiting
- **WHEN** the order is `PENDING_MATCH` or `REMATCHING`
- **THEN** the blind-runner order flow SHALL offer a "keep waiting" action that extends the backend waiting window
- **AND** the action SHALL be reachable by VoiceOver and included in repeat-status speech
- **AND** the app SHALL NOT require a second confirmation for it, because it is idempotent and preserves the order

#### Scenario: Keep waiting is dispatched by status
- **WHEN** the blind runner activates "keep waiting"
- **THEN** the app SHALL call the extension endpoint that matches the current status, and only that one
- **AND** the app SHALL NOT retry the other extension endpoint after a rejection, because the two accept mutually exclusive states and a rejection means the local status is stale
- **AND** the app SHALL refresh canonical order detail after a rejection

#### Scenario: Keep waiting succeeds
- **WHEN** the extension call succeeds
- **THEN** the app SHALL announce that the request was sent, in progressive rather than completed wording
- **AND** the announcement SHALL NOT state any concrete extended duration, because the window length is backend configuration the client cannot read
- **AND** the app SHALL keep the order in its current status, because a successful extension does not change status

#### Scenario: Extension limit is reached
- **WHEN** the extension call is rejected with the keep-waiting limit error
- **THEN** the app SHALL announce that the extension limit has been reached and state what remains possible
- **AND** the app SHALL remove the "keep waiting" action for this order rather than leave a control that can only fail

#### Scenario: Cancellation warning arrives while waiting
- **WHEN** the coordinator routes the order cancellation warning notification
- **THEN** the app SHALL announce it
- **AND** the "keep waiting" action SHALL already be present, because it is driven by order status rather than by the notification

#### Scenario: Volunteer location is available
- **WHEN** the order is `PENDING_ACCEPT`, `DRIVER_EN_ROUTE`, or `DRIVER_ARRIVED` and the coordinator routes a fresh `VOLUNTEER_LOCATION_UPDATE` from `/ws/blind`
- **THEN** the app SHALL calculate distance from the volunteer's latest coordinates to `order.startLatitude/startLongitude`
- **AND** the blind-runner UI and repeated status speech SHALL use "距出发地点约 X"
- **AND** the app SHALL NOT use "距您" for this distance
- **AND** the app SHALL hide distance when the order start coordinate or volunteer location is unavailable
- **AND** service-session peer presentation SHALL remain owned by `enable-live-escort-location-and-track-summary`

#### Scenario: REST fallback is used before service
- **WHEN** an eligible pre-service order has disconnected or stale WebSocket volunteer location
- **THEN** the app SHALL use the typed `GET /api/blind/volunteer-location` fallback according to its freshness/no-data contract
