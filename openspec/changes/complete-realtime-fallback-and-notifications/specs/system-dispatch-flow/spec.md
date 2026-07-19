## MODIFIED Requirements

### Requirement: Volunteer receives timed dispatch prompts
The iOS volunteer client SHALL receive backend `NEW_ORDER` prompts through the app-lifetime realtime coordinator and retain accept/decline-only behavior.

#### Scenario: Dispatch arrives during navigation
- **WHEN** `/ws/volunteer` receives `NEW_ORDER` while volunteer home is not mounted
- **THEN** the coordinator SHALL retain and present the prompt using its backend `dispatchTimeoutSeconds`
- **AND** no public-order-pool or "later" action SHALL be introduced

### Requirement: Blind runner state updates remain status driven
The iOS blind-runner order flow SHALL receive status and pre-service volunteer-location signals through the app-lifetime coordinator with REST fallback when documented.

#### Scenario: Volunteer status changes
- **WHEN** the coordinator receives a status event for the blind runner's order
- **THEN** the order ViewModel SHALL refresh canonical REST detail

#### Scenario: Pre-service WebSocket location is unavailable
- **WHEN** an eligible pre-service order has disconnected or stale volunteer-location WebSocket data
- **THEN** the app SHALL use the typed `GET /api/blind/volunteer-location` fallback
