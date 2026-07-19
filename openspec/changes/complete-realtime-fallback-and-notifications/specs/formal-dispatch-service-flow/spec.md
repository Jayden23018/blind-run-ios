## MODIFIED Requirements

### Requirement: Blind runner state updates remain status driven
The iOS blind-runner order screens SHALL update from app-lifetime WebSocket routing and REST polling without exposing backend dispatch rounds.

#### Scenario: Volunteer accepts dispatch
- **WHEN** the coordinator routes `ORDER_STATUS_CHANGED` or polling returns `PENDING_ACCEPT`
- **THEN** the app SHALL refresh and show the canonical "待出发" state
- **AND** TTS SHALL use local order-detail copy rather than duplicate lifecycle template speech

#### Scenario: No volunteer is available
- **WHEN** WebSocket or polling returns `NO_VOLUNTEER`
- **THEN** the app SHALL show and announce a no-volunteer terminal state

#### Scenario: Pre-service volunteer location is available
- **WHEN** the order is `PENDING_ACCEPT`, `DRIVER_EN_ROUTE`, or `DRIVER_ARRIVED` and the coordinator routes a fresh `VOLUNTEER_LOCATION_UPDATE`
- **THEN** existing pre-service distance-to-start behavior SHALL continue
- **AND** service-session peer presentation SHALL remain owned by `enable-live-escort-location-and-track-summary`

#### Scenario: REST fallback is used before service
- **WHEN** an eligible pre-service order has disconnected or stale WebSocket volunteer location
- **THEN** the app SHALL use the typed `GET /api/blind/volunteer-location` fallback according to its freshness/no-data contract

### Requirement: Realtime feature events survive navigation
Order, dispatch, peer-location, separation-alert, and safety events SHALL be routed independently of individual screen lifetimes.

#### Scenario: Relevant feature screen is not mounted
- **WHEN** a typed event for the active user/order arrives during navigation
- **THEN** the app-lifetime coordinator SHALL retain or route the actionable signal
- **AND** the destination feature SHALL reconcile with authoritative backend state when presented
