## MODIFIED Requirements

### Requirement: Transport recovery preserves feature continuity
The app SHALL preserve serialized sends, 30-second heartbeat health for both roles, reconnect backoff, unknown-message tolerance, and dependent feature recovery across disconnection and reconnection.

#### Scenario: WebSocket reconnects during live escort
- **WHEN** a role WebSocket reconnects for an eligible escort session
- **THEN** the coordinator SHALL request canonical active-order refresh
- **AND** it SHALL signal the live escort coordinator to send current location immediately and resume five-second cadence

### Requirement: Peer-location events are routed by order and role
The app-lifetime realtime coordinator SHALL route fresh `VOLUNTEER_LOCATION_UPDATE` and `BLIND_LOCATION_UPDATE` samples to the matching live escort feature while maintaining order/account isolation.

#### Scenario: Matching peer sample arrives
- **WHEN** a validated sample matches the active participant order and role direction
- **THEN** it SHALL be delivered to the live escort session exactly once

#### Scenario: Session identity changes
- **WHEN** logout, account change, terminal order state, or participant loss occurs
- **THEN** retained peer samples SHALL be cleared before any new session is routed

### Requirement: Separation alerts use high-priority safety-aware routing
The coordinator SHALL route separation alerts with high priority and deduplicate only repeated delivery of the same stable event identity.

#### Scenario: Distinct separation events share text
- **WHEN** two separation events have different stable IDs but identical copy
- **THEN** both SHALL be delivered independently
