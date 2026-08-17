## MODIFIED Requirements

### Requirement: Volunteer receives timed dispatch prompts
The iOS volunteer client SHALL receive backend `NEW_ORDER` prompts through the app-lifetime realtime coordinator and retain accept/decline-only behavior.

#### Scenario: New order dispatch arrives
- **WHEN** `/ws/volunteer` receives a `NEW_ORDER` message
- **THEN** the app SHALL show a 30-second prompt using `dispatchTimeoutSeconds`
- **AND** the prompt SHALL display order time, start address, distance, priority, optional pace, guide dog, notes, and optional start coordinates when present

#### Scenario: Dispatch arrives during navigation
- **WHEN** `/ws/volunteer` receives `NEW_ORDER` while volunteer home is not mounted
- **THEN** the coordinator SHALL retain and present the prompt using its backend `dispatchTimeoutSeconds`
- **AND** no public-order-pool or "later" action SHALL be introduced

#### Scenario: Volunteer accepts dispatch
- **WHEN** the volunteer taps accept on a dispatch prompt
- **THEN** the app SHALL report current location if available
- **AND** the app SHALL call `POST /api/orders/{id}/respond` with `action = ACCEPT`
- **AND** the app SHALL navigate to the accepted order detail or service flow on success

#### Scenario: Volunteer declines or times out
- **WHEN** the volunteer taps decline or the prompt timer reaches zero
- **THEN** the app SHALL call `POST /api/orders/{id}/respond` with `action = DECLINE` when appropriate
- **AND** the app SHALL dismiss the prompt without showing a "later" business action

### Requirement: Blind runner state updates remain status driven
The iOS blind-runner order flow SHALL receive status and pre-service volunteer-location signals through the app-lifetime coordinator with REST fallback when documented.

#### Scenario: Volunteer accepts dispatch
- **WHEN** the blind runner receives `ORDER_STATUS_CHANGED` or polling returns `PENDING_ACCEPT`
- **THEN** the app SHALL update the UI to show a volunteer has accepted
- **AND** TTS SHALL announce the accepted volunteer state

#### Scenario: Volunteer status changes
- **WHEN** the coordinator receives a status event for the blind runner's order
- **THEN** the order ViewModel SHALL refresh canonical REST detail

#### Scenario: No volunteer is available
- **WHEN** WebSocket or polling returns `NO_VOLUNTEER`
- **THEN** the app SHALL show a no-volunteer terminal state
- **AND** TTS SHALL announce that no volunteer is currently available

#### Scenario: Volunteer location is available
- **WHEN** the order is `DRIVER_EN_ROUTE` or `DRIVER_ARRIVED`
- **THEN** the app SHALL display volunteer location from `VOLUNTEER_LOCATION_UPDATE`
- **AND** the app SHALL use `GET /api/blind/volunteer-location` as a fallback when WebSocket is unavailable

#### Scenario: Pre-service WebSocket location is unavailable
- **WHEN** an eligible pre-service order has disconnected or stale volunteer-location WebSocket data
- **THEN** the app SHALL use the typed `GET /api/blind/volunteer-location` fallback
