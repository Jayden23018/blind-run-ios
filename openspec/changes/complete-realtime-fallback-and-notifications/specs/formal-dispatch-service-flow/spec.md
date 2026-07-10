## MODIFIED Requirements

### Requirement: Blind runner state updates remain status driven
The iOS blind-runner order screens SHALL update from WebSocket notifications and REST polling without exposing backend dispatch rounds or another person's real-time position.

#### Scenario: Volunteer accepts dispatch
- **WHEN** the blind runner receives `ORDER_STATUS_CHANGED` or polling returns `PENDING_ACCEPT`
- **THEN** the app SHALL update the UI to show "待出发"
- **AND** TTS SHALL use local order-detail copy that says the volunteer has accepted, includes appointment time and start address when available, and tells the blind runner to go to or wait at the appointment start address
- **AND** the app SHALL NOT speak backend lifecycle `APP_NOTIFICATION` template text directly while an active order is present

#### Scenario: No volunteer is available
- **WHEN** WebSocket or polling returns `NO_VOLUNTEER`
- **THEN** the app SHALL show a no-volunteer terminal state
- **AND** TTS SHALL announce that no volunteer is currently available

#### Scenario: WebSocket volunteer distance is available
- **WHEN** the order is `PENDING_ACCEPT`, `DRIVER_EN_ROUTE`, or `DRIVER_ARRIVED` and `/ws/blind` receives a fresh `VOLUNTEER_LOCATION_UPDATE`
- **THEN** the app SHALL calculate distance from the volunteer's transient latest coordinates to `order.startLatitude/startLongitude`
- **AND** the blind-runner UI and repeated status speech SHALL use "距出发地点约 X"
- **AND** the app SHALL NOT expose the volunteer's coordinate, marker, movement direction, route, track, or "距您" wording

#### Scenario: REST volunteer distance fallback is used
- **WHEN** the order is `DRIVER_EN_ROUTE` or `DRIVER_ARRIVED` and WebSocket volunteer location is disconnected or stale
- **THEN** the app SHALL request `GET /api/blind/volunteer-location`
- **AND** it SHALL use a fresh response only to calculate "距出发地点约 X"
- **AND** it SHALL apply the same privacy restrictions as WebSocket location

#### Scenario: Volunteer distance cannot be calculated
- **WHEN** the order start coordinate, volunteer location, or freshness requirement is unavailable
- **THEN** the app SHALL hide distance and raw coordinates
- **AND** repeated status speech SHALL say that volunteer position is temporarily unavailable only when that context is useful
