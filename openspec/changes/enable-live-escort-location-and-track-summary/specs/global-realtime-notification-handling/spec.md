## MODIFIED Requirements

### Requirement: Transport recovery preserves feature continuity
The app SHALL preserve serialized sends, 30-second heartbeat health for both roles, reconnect backoff, unknown-message tolerance, and dependent feature recovery across disconnection and reconnection.

#### Scenario: WebSocket reconnects during live escort
- **WHEN** a role WebSocket reconnects for an eligible escort session
- **THEN** the coordinator SHALL request canonical active-order refresh
- **AND** it SHALL signal the live escort coordinator to send current location immediately and resume five-second cadence

#### Scenario: An obsolete socket fails after replacement
- **WHEN** a receive, send, heartbeat, or close callback belongs to an older connection generation
- **THEN** it SHALL be ignored without changing the replacement socket state
- **AND** one active generation SHALL schedule at most one reconnect

#### Scenario: Volunteer socket reconnects while waiting for dispatch
- **WHEN** the volunteer WebSocket reconnects outside an active escort session
- **THEN** iOS SHALL immediately report the latest valid real volunteer location and refresh `GET /api/volunteer/dispatch-summary`
- **AND** missing real location SHALL produce visible and spoken degraded-dispatch guidance

#### Scenario: A home refresh is cancelled by navigation or lifecycle transition
- **WHEN** external navigation, lock/background transition, or SwiftUI task replacement cancels an in-flight volunteer or blind-runner home refresh
- **THEN** the visible loading state SHALL be released immediately
- **AND** expected task cancellation SHALL NOT be presented as a network failure
- **AND** the next foreground refresh SHALL remain available

#### Scenario: Multiple sources request the same home refresh
- **WHEN** lifecycle, WebSocket reconnect, timer, or manual actions request the same home endpoint while its request is in flight
- **THEN** the triggers SHALL coalesce into the existing request
- **AND** they SHALL NOT cancel, restart, or extend its original 20-second deadline
- **AND** retained content and local navigation SHALL remain usable

### Requirement: Validated order-status events update matching local flows before detail recovery
The app-lifetime realtime coordinator SHALL publish a `RealtimeOrderStatusUpdate` only for the associated active order when `fromStatus` and `toStatus` are known enum values and the original status matches the current in-memory state when available.

#### Scenario: Matching status event arrives while detail query is suspended
- **WHEN** a valid associated `ORDER_STATUS_CHANGED` advances the current order while its REST detail query is pending
- **THEN** the blind-runner and volunteer flows SHALL apply the target status immediately
- **AND** the blind-runner flow SHALL make the corresponding accessible/TTS announcement
- **AND** full detail recovery SHALL continue independently in the background

#### Scenario: Status event is invalid, duplicated, unrelated, or late
- **WHEN** order association fails, either status is unknown, the same transition is repeated, or `fromStatus` no longer matches the current status
- **THEN** the event SHALL NOT mutate local order state
- **AND** it MAY request a bounded safe REST refresh

#### Scenario: An older REST response arrives after realtime advancement
- **WHEN** a detail or summary request began before a valid realtime transition and returns the prior status afterward
- **THEN** the shared status reconciler SHALL reject the regression
- **AND** no home, detail, speech, or escort-session state SHALL move backward

#### Scenario: A status identity is replayed after reconnect
- **WHEN** an `ORDER_STATUS_CHANGED` repeats the same valid UUID `messageId` and the same order/from/to fingerprint
- **THEN** the coordinator SHALL discard it before UI update, speech, or REST refresh
- **AND** the bounded identity cache SHALL survive physical WebSocket reconnects within the same login session

#### Scenario: A status identity collides with different content
- **WHEN** an already retained UUID `messageId` is reused with a different order or status fingerprint
- **THEN** the coordinator SHALL NOT apply either colliding candidate as a new transition
- **AND** the first collision MAY request one bounded safe REST refresh while repeated collision delivery SHALL be dropped

#### Scenario: A legacy status event has no valid UUID
- **WHEN** an otherwise valid associated status event omits `messageId` or supplies a malformed UUID
- **THEN** the client SHALL record an anonymous contract anomaly
- **AND** it SHALL continue association and state reconciliation for backward compatibility

#### Scenario: Structured status and lifecycle template arrive in either order
- **WHEN** `ORDER_STATUS_CHANGED` and its parallel lifecycle `APP_NOTIFICATION` describe the same target status
- **THEN** the app SHALL announce the client-authored lifecycle copy exactly once
- **AND** the suppression SHALL still apply when a terminal status removed the active order before the template arrived
- **AND** safety alerts and non-lifecycle notifications SHALL remain unaffected

#### Scenario: Realtime delivery is absent
- **WHEN** the WebSocket is disconnected or a status event is missed
- **THEN** REST detail recovery and documented five-second blind-order polling SHALL remain available
- **AND** a late fallback response SHALL still be subject to the shared status reconciler

### Requirement: Dispatch delivery is diagnosable without exposing private data
The app SHALL retain bounded in-memory diagnostics that distinguish volunteer transport connection, `NEW_ORDER` receipt, decode failure, coordinator retention, and UI presentation.

#### Scenario: NEW_ORDER cannot be decoded
- **WHEN** a `NEW_ORDER` envelope is received but its typed payload is invalid
- **THEN** the receiver SHALL remain available for later messages
- **AND** diagnostics SHALL contain only role, transport state/generation, message type, timestamp, and failed field
- **AND** diagnostics SHALL NOT contain JWTs, coordinates, phone numbers, addresses, or message bodies

### Requirement: Peer-location events are routed by order and role
The app-lifetime realtime coordinator SHALL route fresh `VOLUNTEER_LOCATION_UPDATE` and `BLIND_LOCATION_UPDATE` samples to the matching live escort feature while maintaining order/account isolation.

#### Scenario: Matching peer sample arrives
- **WHEN** a validated sample matches the active participant order and role direction
- **THEN** it SHALL be delivered to the live escort session exactly once

#### Scenario: Peer-location events arrive faster than UI consumption
- **WHEN** repeated valid peer samples for one order and role arrive within one main-actor delivery cycle
- **THEN** only the latest sample SHALL be published for that cycle
- **AND** reliable status and notification events SHALL preserve order and SHALL NOT be dropped

#### Scenario: Session identity changes
- **WHEN** logout, account change, terminal order state, or participant loss occurs
- **THEN** retained peer samples SHALL be cleared before any new session is routed

### Requirement: Separation alerts use high-priority safety-aware routing
The coordinator SHALL route `ESCORT_DISTANCE_ALERT` and `ESCORT_SIGNAL_LOST` with high priority and deduplicate only repeated delivery of the same UUID `messageId` identity.

#### Scenario: Distinct separation events share text
- **WHEN** two separation events have different stable IDs but identical copy
- **THEN** both SHALL be delivered independently
