## ADDED Requirements

### Requirement: Location contracts define GCJ-02 consistently
The canonical HTTP and WebSocket contracts MUST state whether every order, live-location, fallback-location, and track coordinate is GCJ-02 and MUST define handling for pre-migration stored data.

#### Scenario: Client uploads a location
- **WHEN** either role sends `LOCATION_UPDATE`
- **THEN** the backend contract treats `lat/lng` as GCJ-02 with documented bounds and no additional ambiguous conversion

#### Scenario: Backend returns a coordinate
- **WHEN** the backend emits an order, peer, fallback, or track coordinate
- **THEN** its coordinate system is explicitly documented and consistent or individually tagged

### Requirement: Both role sockets support heartbeat
Both `/ws/blind` and `/ws/volunteer` MUST accept `{"type":"PING"}` and return the documented `PONG` payload so iOS can use a 30-second heartbeat for either role.

#### Scenario: Volunteer sends PING
- **WHEN** the authenticated volunteer socket sends a valid `PING`
- **THEN** the server returns `PONG` without affecting dispatch or order state

### Requirement: Live participant locations are forwarded in both directions
The WebSocket contract MUST define five-second client `LOCATION_UPDATE` compatibility and associated-order `VOLUNTEER_LOCATION_UPDATE`/`BLIND_LOCATION_UPDATE` forwarding during `DRIVER_EN_ROUTE`, `DRIVER_ARRIVED`, and `IN_PROGRESS`.

#### Scenario: Participant reports during IN_PROGRESS
- **WHEN** either associated participant sends a valid location during `IN_PROGRESS`
- **THEN** the backend stores/samples it according to the track policy and forwards it to the other participant

### Requirement: Separation alert contract is typed and identifiable
The WebSocket contract MUST define the canonical `ESCORT_DISTANCE_ALERT` envelope, safe role-specific text/TTS, priority, timestamp, and stable event identity.

#### Scenario: Distance exceeds backend threshold
- **WHEN** backend-authoritative comparison triggers a separation alert
- **THEN** both participants receive typed alerts without an order-status mutation

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
- **THEN** the endpoint returns a documented stable error or nullable/empty response shape

### Requirement: Volunteer-track anomaly semantics are versioned
Before iOS displays an abnormality conclusion, the backend contract MUST expose a versioned assessment/threshold or product MUST approve an equivalent versioned client comparison rule.

#### Scenario: Anomaly assessment is available
- **WHEN** both participant tracks are compared for a completed order
- **THEN** the result identifies the applied threshold/version and does not require iOS to infer mutable backend configuration
