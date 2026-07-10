## ADDED Requirements

### Requirement: Realtime events have one app-lifetime routing owner
The iOS app SHALL attach one app-lifetime coordinator to the active `WebSocketService` and SHALL route decoded events to feature-specific state without depending on a particular screen being mounted.

#### Scenario: User navigates away from an order screen
- **WHEN** a relevant order, proximity, dispatch, or safety event arrives while its detail screen is not mounted
- **THEN** the coordinator SHALL retain or route the actionable event to the appropriate feature state
- **AND** returning to the feature SHALL reflect the latest backend state

#### Scenario: Role switch replaces WebSocket service
- **WHEN** a new role token causes `AppState` to replace `WebSocketService`
- **THEN** the coordinator SHALL detach from the old service and subscribe exactly once to the new service

### Requirement: WebSocket status events trigger authoritative refreshes
The iOS app SHALL treat `ORDER_STATUS_CHANGED` as a signal to refresh the affected order and SHALL NOT construct authoritative order detail from the partial WebSocket payload.

#### Scenario: Active order status event arrives
- **WHEN** `ORDER_STATUS_CHANGED` identifies an order visible to the active role
- **THEN** the relevant ViewModel SHALL refresh `GET /api/orders/{id}`
- **AND** UI and lifecycle TTS SHALL use the refreshed canonical status

#### Scenario: Duplicate status events arrive
- **WHEN** equivalent status events for the same order arrive before the current refresh completes
- **THEN** the coordinator SHALL coalesce redundant refresh requests

### Requirement: Foreground notifications respect priority and accessibility
The iOS app SHALL present foreground `APP_NOTIFICATION` messages according to documented priority and SHALL provide equivalent visible, VoiceOver, and TTS feedback when appropriate.

#### Scenario: High-priority notification arrives
- **WHEN** a non-duplicate `HIGH` notification arrives
- **THEN** it SHALL preempt normal foreground presentation
- **AND** the app SHALL immediately announce its safe user-facing text

#### Scenario: Normal notification arrives during high-priority presentation
- **WHEN** a `NORMAL` notification arrives while a high-priority message is active
- **THEN** it SHALL be queued without interrupting the high-priority announcement

#### Scenario: Lifecycle template duplicates local status copy
- **WHEN** an `APP_NOTIFICATION` describes the same lifecycle transition handled by an order refresh
- **THEN** the app SHALL suppress direct template TTS
- **AND** it SHALL speak the canonical local order-status announcement once

### Requirement: Realtime notification deduplication is safety aware
The iOS app SHALL suppress duplicate non-safety foreground messages while preserving distinct safety events identified by event ID.

#### Scenario: Duplicate template notification arrives
- **WHEN** the same normalized message/type is received repeatedly inside the deduplication window
- **THEN** the app SHALL present and speak it only once

#### Scenario: Distinct safety events share copy
- **WHEN** two safety events have different event IDs but the same message text
- **THEN** the app SHALL route both events independently

### Requirement: Transport recovery preserves feature continuity
The app SHALL retain the documented heartbeat, 500ms send interval, reconnect backoff, and REST/order refresh behavior across WebSocket disconnection and reconnection.

#### Scenario: WebSocket reconnects
- **WHEN** a disconnected role WebSocket reconnects
- **THEN** the coordinator SHALL request relevant active-feature refreshes
- **AND** location reporting SHALL resume on the normal timer/current-location path

#### Scenario: Incoming message type is unknown
- **WHEN** the backend sends an unrecognized message type
- **THEN** the app SHALL ignore it safely without disconnecting or presenting raw payload data
