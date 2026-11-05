# global-realtime-notification-handling Specification

## Purpose
TBD - created by archiving change complete-realtime-fallback-and-notifications. Update Purpose after archive.
## Requirements
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

#### Scenario: WebSocket reconnects
- **WHEN** a role WebSocket reconnects
- **THEN** the coordinator SHALL request relevant active-order/summary refreshes
- **AND** it SHALL signal dependent feature coordinators to resume their documented cadence

#### Scenario: Incoming message type is unknown
- **WHEN** the backend sends an unrecognized message type
- **THEN** the app SHALL ignore it safely without disconnecting or presenting raw payload data

### Requirement: Volunteer emergency alert survives app restarts
The app SHALL recover the escorting volunteer's emergency alert from `GET /api/emergency/active` whenever it recovers realtime state (WebSocket reconnect, return to foreground, cold-start session restore), and SHALL show the distance to the runner as a band from the device fix or, failing that, from the server-computed distance.

#### Scenario: Volunteer reopens the app during an open emergency
- **WHEN** a volunteer session recovers and the endpoint returns a non-terminal event that is not `COUNTDOWN`
- **THEN** the volunteer alert SHALL be restored for that event, full screen unless `volunteerConfirmedAt` is set
- **AND** its elapsed time SHALL count from `triggeredAt`, never from a time later than now
- **AND** the volunteer's own SOS state SHALL NOT change

#### Scenario: Event is still counting down
- **WHEN** the endpoint returns an event in `COUNTDOWN`
- **THEN** no volunteer alert SHALL be shown

#### Scenario: Emergency ended while the app was away
- **WHEN** the endpoint returns no open event
- **THEN** any local volunteer alert SHALL be cleared
- **AND** a failed request SHALL leave the current alert unchanged

#### Scenario: Device has no location fix yet
- **WHEN** the alert has no usable device distance and the push carried `distanceBand` `NEARBY`, `CLOSE` or `FAR` with `distanceMeters`
- **THEN** the distance line SHALL show the band for the server distance
- **AND** when the band is `UNKNOWN`, unrecognised or missing, no distance line SHALL be shown

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

### Requirement: Separation alerts use high-priority safety-aware routing
The coordinator SHALL route `ESCORT_DISTANCE_ALERT` and `ESCORT_SIGNAL_LOST` with high priority and deduplicate only repeated delivery of the same UUID `messageId` identity.

#### Scenario: Distinct separation events share text
- **WHEN** two separation events have different stable IDs but identical copy
- **THEN** both SHALL be delivered independently

### Requirement: The overdue-run alert outranks routine progress notifications
`ORDER_OVERDUE` means the run has passed its agreed end time and the runner may be unreachable. The app SHALL present it at high priority regardless of the priority the server template assigns, so that it preempts routine dispatch-progress notifications rather than queueing behind them.

#### Scenario: Server sends the overdue alert at normal priority
- **WHEN** an `ORDER_OVERDUE` notification arrives with a server priority of `NORMAL`
- **THEN** the app SHALL treat it as high priority for banner styling, header traits, and speech queue preemption

#### Scenario: Overdue alert is missed while offline
- **WHEN** an `ORDER_OVERDUE` notification is replayed through offline catch-up
- **THEN** the same elevation SHALL apply, because a late alert queued behind progress notifications is later still

#### Scenario: Any other notification arrives
- **WHEN** a notification whose event type is not `ORDER_OVERDUE` arrives
- **THEN** the app SHALL use the priority the server template assigned, so that elevating everything does not make priority meaningless

#### Scenario: The overdue alert competes with the lifecycle suppression gate
- **WHEN** an `ORDER_OVERDUE` notification arrives while the user has an active order
- **THEN** the app SHALL NOT suppress it as a duplicate of an order-status change, because it announces no order status
- **AND** the suppression decision SHALL be driven by event type rather than by matching body text

#### Scenario: The app is not in the foreground
- **WHEN** the app is backgrounded or terminated
- **THEN** client-side elevation SHALL NOT be relied on for delivery, because push fallback is gated on the server template priority rather than on the client's display priority

