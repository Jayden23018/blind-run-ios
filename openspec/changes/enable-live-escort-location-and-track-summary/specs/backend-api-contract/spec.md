## ADDED Requirements

### Requirement: Location contracts define GCJ-02 consistently
The canonical HTTP and WebSocket contracts MUST state whether every order, live-location, fallback-location, and track coordinate is GCJ-02 and MUST define handling for pre-migration stored data.

#### Scenario: Client uploads a location
- **WHEN** either role sends `LOCATION_UPDATE`
- **THEN** the backend contract treats `lat/lng` as GCJ-02 with documented bounds and no additional ambiguous conversion

#### Scenario: Backend returns a coordinate
- **WHEN** the backend emits an order, peer, fallback, or track coordinate
- **THEN** it is interpreted as GCJ-02 without another conversion
- **AND** historical data is treated as clean GCJ-02 because the backend confirmed all existing write paths used AMap/Tencent coordinates

### Requirement: Both role sockets support heartbeat
Both `/ws/blind` and `/ws/volunteer` MUST accept `{"type":"PING"}` and return the documented `PONG` payload so iOS can use a 30-second heartbeat for either role.

#### Scenario: Volunteer sends PING
- **WHEN** the authenticated volunteer socket sends a valid `PING`
- **THEN** the server returns `PONG` without affecting dispatch or order state

### Requirement: Order status changes are structured and replay-identifiable
Every persisted lifecycle transition to `DRIVER_EN_ROUTE`, `DRIVER_ARRIVED`, `IN_PROGRESS`, or `COMPLETED` MUST emit one `ORDER_STATUS_CHANGED` to each associated role socket. The flat payload MUST include UUID `messageId`, `orderId`, `fromStatus`, `toStatus`, `message`, `ttsText`, `priority`, and timestamp.

#### Scenario: A volunteer advances an accepted order
- **WHEN** a valid status transition endpoint persists the next order status
- **THEN** `/ws/blind` and `/ws/volunteer` each receive an associated structured status event
- **AND** each role's replay of that same transition retains its original `messageId`

#### Scenario: The transport replays a status event
- **WHEN** an unacknowledged or reconnect-recovered status event is delivered again to the same role
- **THEN** its UUID `messageId`, order identity, and from/to statuses remain unchanged

### Requirement: Live participant locations are forwarded in both directions
The WebSocket contract MUST define five-second client `LOCATION_UPDATE` compatibility and associated-order `VOLUNTEER_LOCATION_UPDATE`/`BLIND_LOCATION_UPDATE` forwarding during `DRIVER_EN_ROUTE`, `DRIVER_ARRIVED`, and `IN_PROGRESS`.

#### Scenario: Participant reports during IN_PROGRESS
- **WHEN** either associated participant sends a valid location during `IN_PROGRESS`
- **THEN** the backend stores/samples it according to the track policy and forwards it to the other participant

### Requirement: Separation alert contract is flat and machine-identifiable
The WebSocket contract MUST define every template notification as a flat `APP_NOTIFICATION` with outer UUID `messageId`, template `eventType`, and timestamp. Both safety templates MUST use `priority: HIGH`, role-specific body/TTS, and `eventType` values `ESCORT_DISTANCE_ALERT` or `ESCORT_SIGNAL_LOST`. Production MUST NOT be documented as using nested `data` or a current `orderId` field.

#### Scenario: Distance exceeds backend threshold
- **WHEN** backend-authoritative comparison triggers a separation alert
- **THEN** both participants receive flat high-priority alerts without an order-status mutation

#### Scenario: Current alert omits order ID
- **WHEN** an authenticated safety-template `APP_NOTIFICATION` has `messageId` and `eventType` but no `orderId`
- **THEN** iOS presents it only while exactly one owned order is `IN_PROGRESS`

### Requirement: Order track endpoint is typed and participant authorized
The canonical API contract MUST define `GET /api/orders/{id}/track` for the two order participants with ordered blind/volunteer points and nullable/partial per-role statistics.

#### Scenario: Participant requests completed track
- **WHEN** an authenticated order participant requests a completed order track
- **THEN** the response includes `blindTrack`, `blindStats`, `volunteerTrack`, and `volunteerStats` using the documented GCJ-02/time formats

#### Scenario: Non-participant requests track
- **WHEN** an authenticated user who is not an order participant requests the track
- **THEN** the backend rejects access with the unified authorization error

#### Scenario: Track is unavailable or incomplete
- **WHEN** the order is not complete, is legacy data, or lacks enough sampled points
- **THEN** the endpoint returns guaranteed order `status`, each raw role track with 0/1/multiple points, and `TrackStats(0, 0, null)` only for each role below two points rather than an error

### Requirement: Volunteer-track anomaly semantics are versioned
Before iOS displays an abnormality conclusion, the backend contract MUST expose a versioned assessment/threshold or product MUST approve an equivalent versioned client comparison rule.

#### Scenario: Anomaly assessment is available
- **WHEN** both participant tracks are compared for a completed order
- **THEN** the result identifies the applied threshold/version and does not require iOS to infer mutable backend configuration
