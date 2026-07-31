## ADDED Requirements

### Requirement: Realtime events have one app-lifetime routing owner
The iOS app SHALL attach one app-lifetime coordinator to the active `WebSocketService` and route decoded events without depending on a particular screen being mounted.

#### Scenario: User navigates away from an order screen
- **WHEN** a relevant order, dispatch, peer-location, separation, notification, or safety event arrives while its feature screen is absent
- **THEN** the coordinator SHALL retain or route the signal to the appropriate feature state
- **AND** returning to the feature SHALL reconcile with the latest backend state

#### Scenario: Role or token replaces the WebSocket service
- **WHEN** logout, role switch, token replacement, or account change replaces the role WebSocket
- **THEN** the coordinator SHALL detach from the old service and subscribe exactly once to the new service
- **AND** it SHALL clear prior-user in-memory event state

### Requirement: WebSocket status events trigger authoritative refreshes
The iOS app SHALL treat `ORDER_STATUS_CHANGED` as a signal to refresh the affected order and SHALL NOT construct authoritative order detail from a partial WebSocket payload.

#### Scenario: Active order status event arrives
- **WHEN** `ORDER_STATUS_CHANGED` identifies an order visible to the active role
- **THEN** the relevant ViewModel SHALL refresh `GET /api/orders/{id}`
- **AND** UI and lifecycle TTS SHALL use the refreshed status

#### Scenario: Duplicate status events arrive
- **WHEN** equivalent status events for the same order arrive before refresh completes
- **THEN** the coordinator SHALL coalesce redundant refresh requests

### Requirement: Dispatch prompts survive navigation
The coordinator SHALL route and retain an unhandled `NEW_ORDER` prompt until it is accepted, declined, expired, invalidated by backend state, or the authenticated role changes.

#### Scenario: Prompt arrives outside volunteer home
- **WHEN** an eligible volunteer receives `NEW_ORDER` while another screen is mounted
- **THEN** the timed prompt SHALL still be presented with its backend deadline

### Requirement: Peer-location events are routed by order and role
The coordinator SHALL decode and route both peer-location directions as validated typed samples without deciding map or summary presentation.

#### Scenario: Associated peer location arrives
- **WHEN** `VOLUNTEER_LOCATION_UPDATE` or `BLIND_LOCATION_UPDATE` matches the active user's associated order
- **THEN** the coordinator SHALL publish the typed sample to the relevant feature
- **AND** it SHALL NOT log raw coordinates

#### Scenario: Wrong-order or invalid coordinate arrives
- **WHEN** a peer sample references another order or contains coordinates outside valid ranges
- **THEN** the coordinator SHALL ignore it without changing visible feature state

### Requirement: Foreground notifications respect priority and accessibility
Foreground notifications SHALL follow documented priority and provide equivalent visible, VoiceOver, and TTS feedback where appropriate.

#### Scenario: High-priority notification arrives
- **WHEN** a non-duplicate `HIGH` notification arrives
- **THEN** it SHALL preempt normal foreground presentation and immediately announce safe user-facing text

#### Scenario: Lifecycle notification duplicates refreshed status
- **WHEN** a notification describes the same lifecycle transition handled by an order refresh
- **THEN** direct template TTS SHALL be suppressed and canonical local status SHALL be spoken once

### Requirement: Realtime deduplication is safety aware
The app SHALL suppress duplicate non-safety messages while preserving distinct safety and separation events identified by stable event ID.

#### Scenario: Duplicate general notification arrives
- **WHEN** the same documented identity or normalized fallback key repeats inside the deduplication window
- **THEN** it SHALL be presented and spoken only once

#### Scenario: Distinct safety events share copy
- **WHEN** two events have different stable IDs but identical text
- **THEN** both SHALL be routed independently

### Requirement: Transport recovery preserves feature continuity
The app SHALL preserve serialized sends, the 500 ms minimum interval, reconnect backoff, unknown-message tolerance, and REST refresh behavior across disconnection and reconnection.

#### Scenario: WebSocket reconnects
- **WHEN** a role WebSocket reconnects
- **THEN** the coordinator SHALL request relevant active-order/summary refreshes
- **AND** it SHALL signal dependent feature coordinators to resume their documented cadence

#### Scenario: Incoming message type is unknown
- **WHEN** the backend sends an unrecognized message type
- **THEN** the app SHALL ignore it safely without disconnecting or presenting raw payload data
