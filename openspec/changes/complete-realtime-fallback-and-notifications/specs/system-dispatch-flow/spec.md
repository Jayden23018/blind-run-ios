## MODIFIED Requirements

### Requirement: Blind runner state updates remain status driven
The iOS blind-runner order screens SHALL update from WebSocket notifications and REST polling without exposing backend dispatch rounds or another person's real-time position.

#### Scenario: Volunteer accepts dispatch
- **WHEN** the blind runner receives `ORDER_STATUS_CHANGED` or polling returns `PENDING_ACCEPT`
- **THEN** the app SHALL update the UI to show a volunteer has accepted
- **AND** TTS SHALL announce the accepted volunteer state

#### Scenario: No volunteer is available
- **WHEN** WebSocket or polling returns `NO_VOLUNTEER`
- **THEN** the app SHALL show a no-volunteer terminal state
- **AND** TTS SHALL announce that no volunteer is currently available

#### Scenario: Fresh volunteer location is available
- **WHEN** the order is `PENDING_ACCEPT`, `DRIVER_EN_ROUTE`, or `DRIVER_ARRIVED` and `/ws/blind` provides a fresh `VOLUNTEER_LOCATION_UPDATE`
- **THEN** the app SHALL calculate and display only approximate volunteer distance to the fixed order start point
- **AND** the app SHALL NOT display the volunteer's coordinate, live marker, direction, route, track, or distance to the blind runner

#### Scenario: WebSocket volunteer location is unavailable
- **WHEN** the order is `DRIVER_EN_ROUTE` or `DRIVER_ARRIVED` and WebSocket location is disconnected or stale
- **THEN** the app SHALL use `GET /api/blind/volunteer-location` as a distance-calculation fallback
- **AND** the same distance-only privacy restrictions SHALL apply

#### Scenario: No fresh distance source exists
- **WHEN** order-start coordinates or a fresh volunteer-location source are unavailable
- **THEN** the app SHALL hide volunteer distance
- **AND** it SHALL present a concise location-unavailable status without exposing stale coordinates
