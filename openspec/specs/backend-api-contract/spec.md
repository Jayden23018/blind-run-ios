# backend-api-contract Specification

## Purpose
Define the external cloud backend API and WebSocket contract requirements that the native iOS frontend depends on.
## Requirements
### Requirement: API contract documents the external cloud service

The canonical OpenAPI contract MUST describe the external service consumed by the iOS frontend and MUST declare `http://47.114.113.171` as its only server.

#### Scenario: Contract validation
- **WHEN** the canonical OpenAPI file is inspected
- **THEN** it contains one server entry for `http://47.114.113.171` and no local or placeholder production server

### Requirement: API contract documents volunteer order response endpoint

The canonical API contract MUST define `POST /api/orders/{id}/respond` as the volunteer endpoint for accepting or declining an order dispatch.

#### Scenario: Volunteer accepts an order
- **WHEN** a volunteer accepts an order
- **THEN** the client sends `POST /api/orders/{id}/respond`
- **AND** the request body contains `{"action":"ACCEPT"}`
- **AND** a successful response moves the order to `PENDING_ACCEPT`

#### Scenario: Volunteer declines a dispatch
- **WHEN** a volunteer declines a dispatch prompt
- **THEN** the client sends `POST /api/orders/{id}/respond`
- **AND** the request body contains `{"action":"DECLINE"}`
- **AND** the order remains available according to backend dispatch rules

### Requirement: Volunteer dispatch requires recent WebSocket location

The canonical integration contract MUST require volunteers to connect `/ws/volunteer` and send a `LOCATION_UPDATE` before they can receive order dispatches or respond to dispatched orders.

#### Scenario: Volunteer becomes eligible for dispatch
- **WHEN** a volunteer is available and online
- **AND** the volunteer sends `{"type":"LOCATION_UPDATE","lat":number,"lng":number}` over `/ws/volunteer`
- **AND** the reported location is within 10 km of an order start point
- **THEN** the backend may include the order in `/api/orders/available` or send `NEW_ORDER`

#### Scenario: Volunteer responds before dispatch eligibility
- **WHEN** a volunteer sends `POST /api/orders/{id}/respond`
- **AND** the order has not been dispatched to that volunteer
- **THEN** the backend returns a business error such as `ORDER_DISPATCH_MISMATCH`

### Requirement: API contract documents volunteer service-start endpoint
The canonical API contract MUST define `POST /api/orders/{id}/start-service` as the endpoint for starting service after arrival. Since backend #346 both the volunteer and the blind runner of the order MAY call it; the first call wins.

#### Scenario: Volunteer starts service
- **WHEN** a volunteer starts service for an order in `DRIVER_ARRIVED`
- **THEN** the client sends `POST /api/orders/{id}/start-service`
- **AND** the request has no body
- **AND** a successful response moves the order to `IN_PROGRESS`

#### Scenario: Blind runner starts service
- **WHEN** the blind runner starts service for an order in `DRIVER_ARRIVED`
- **THEN** the client sends `POST /api/orders/{id}/start-service` with the blind-runner token and no body
- **AND** the backend records the runner's consent and moves the order to `IN_PROGRESS`

#### Scenario: The other participant already started
- **WHEN** either participant calls `POST /api/orders/{id}/start-service` for an order already in `IN_PROGRESS`
- **THEN** the backend returns 200 without an error

#### Scenario: Service start is rejected outside arrival state
- **WHEN** a participant calls `POST /api/orders/{id}/start-service` for an order neither in `DRIVER_ARRIVED` nor in `IN_PROGRESS`
- **THEN** the backend returns the unified error response with `INVALID_ORDER_STATUS`

### Requirement: API contract types the volunteer-location fallback
The canonical API contract MUST define a typed response for `GET /api/blind/volunteer-location` containing optional latitude, longitude, order identity, status, and an authoritative `updatedAt` timestamp or a documented no-data response.

#### Scenario: Fresh fallback location exists
- **WHEN** the authenticated blind runner has an eligible pre-service order with recent volunteer location
- **THEN** the endpoint returns the coordinate, matching order identity/status, and documented timestamp format

#### Scenario: Fallback location is unavailable
- **WHEN** no eligible order or recent volunteer location exists
- **THEN** the endpoint returns the documented empty-data or stable error shape without stale coordinates

### Requirement: Realtime notification fields are contractually defined
The canonical WebSocket contract MUST define notification envelope, priority, timestamp, event identity when available, and TTS/display fields used by iOS foreground handling.

#### Scenario: App notification is emitted
- **WHEN** the backend sends a general app notification
- **THEN** the payload uses one documented envelope and contains display text, optional TTS text, priority, timestamp, and stable identity semantics

### Requirement: Both peer-location directions are contractually defined
The canonical WebSocket contract MUST define `VOLUNTEER_LOCATION_UPDATE` and `BLIND_LOCATION_UPDATE` with order ID, latitude, longitude, and timestamp semantics so the global coordinator can route them without parsing raw feature-specific payloads.

#### Scenario: Backend forwards a peer location
- **WHEN** an eligible participant location is forwarded to the associated order participant
- **THEN** the message identifies the location owner by message type and contains the associated order ID and documented timestamp

### Requirement: Separation alerts have a stable realtime contract
The canonical WebSocket contract MUST define the production separation-alert message envelope, event type, priority, event identity, safe display text, and TTS text.

#### Scenario: Separation alert is emitted
- **WHEN** the backend detects that participants exceed the configured separation threshold
- **THEN** both role sockets receive a typed high-priority alert that can be routed and deduplicated without matching localized text

### Requirement: API contract defines current-session validation
The canonical API contract MUST define `GET /api/auth/me` as an authenticated operation that returns the current non-deleted user identity and optional active-role information needed to hydrate the iOS session.

#### Scenario: Current session is valid
- **WHEN** iOS sends a non-blacklisted Bearer token to `GET /api/auth/me`
- **THEN** the backend returns a structured current-user response containing user ID and an active role that may be absent or `UNSET` before first role selection

#### Scenario: Current session is not valid
- **WHEN** the token is expired, blacklisted, or belongs to a deleted user
- **THEN** the backend returns the unified unauthorized response

### Requirement: API contract defines token-revoking logout
The canonical API contract MUST define `POST /api/auth/logout` as an authenticated operation that blacklists the presented JWT and returns a structured success response.

#### Scenario: Logged-out token is reused
- **WHEN** a token has been accepted by `POST /api/auth/logout`
- **THEN** subsequent authenticated HTTP and WebSocket use of that token is rejected

### Requirement: API contract defines self-service soft deletion
The canonical API contract MUST define the authenticated behavior of `DELETE /api/users/{id}` for self-service account deletion, including ownership enforcement, active-order rejection, token invalidation, and phone-number reuse.

#### Scenario: User deletes their own eligible account
- **WHEN** the authenticated user deletes their own ID without a blocking order
- **THEN** the backend soft-deletes the account, invalidates its active authentication, and returns a structured success response

#### Scenario: User attempts to delete another account
- **WHEN** the path ID does not belong to the authenticated user
- **THEN** the backend rejects the request with a unified authorization error

#### Scenario: Active order prevents deletion
- **WHEN** account deletion would orphan an active service order
- **THEN** the backend rejects deletion with a stable business error and leaves the account active

### Requirement: API contract defines unified rate-limit responses
The canonical API contract MUST document HTTP 429 responses for auth, registration, and general rate-limit buckets with a stable error code and retry interval.

#### Scenario: A rate-limit bucket is exhausted
- **WHEN** a request exceeds its backend bucket limit
- **THEN** the backend returns HTTP 429 with the unified error shape
- **AND** the response provides a machine-readable retry interval through `Retry-After` or a documented response field

### Requirement: API contract documents native Step 3 initialization
The canonical API contract MUST define `POST /api/volunteer/registration/step3/face-verify/init` as a JWT-authenticated request whose body contains only the Alibaba Cloud SDK `metaInfo` string and whose successful native SDK response contains `status = PENDING` and a non-empty `certifyId`.

#### Scenario: Native Step 3 initialization succeeds
- **WHEN** the authenticated iOS client submits a non-empty `metaInfo`
- **THEN** the backend derives the current user from the JWT
- **AND** the response contains `status = PENDING` and a non-empty `certifyId`
- **AND** the response does not require `certifyUrl`

#### Scenario: Native Step 3 initialization fails
- **WHEN** the backend cannot initialize Alibaba Cloud face verification
- **THEN** the response contains `status = ERROR` and a user-facing `message`
- **AND** the response does not present the failure as a successful `PENDING` response

### Requirement: Native Step 3 initialization creates a fresh ID_PRO attempt
The external backend MUST create a new single-use Alibaba Cloud App SDK `ID_PRO` verification attempt for every accepted Step 3 init request and MUST NOT reuse or cache a previous `certifyId`.

#### Scenario: Authenticated volunteer starts a new attempt
- **WHEN** the authenticated volunteer submits the current non-empty MetaInfo
- **THEN** the backend uses a unique `OuterOrderNo`, the configured `SceneId`, `ProductCode = ID_PRO`, JWT-derived `UserId`, `CertType = IDENTITY_CARD`, Step 1 approved `CertName` and `CertNo`, and `Model = MULTI_ACTION`
- **AND** the returned `certifyId` is newly issued for that attempt

#### Scenario: Volunteer retries after an SDK failure
- **WHEN** the client retries Step 3 after code `1001`, cancellation, or another non-submitted SDK failure
- **THEN** the backend initializes a different Alibaba Cloud attempt instead of returning the prior `certifyId`

### Requirement: API contract documents native Step 3 result lookup
The canonical API contract MUST define `POST /api/volunteer/registration/step3/face-verify/result` as accepting `certifyId` and returning one of `PENDING`, `APPROVED`, `REJECTED`, or `ERROR`.

#### Scenario: Native result remains pending
- **WHEN** Alibaba Cloud has not produced a final result for the submitted `certifyId`
- **THEN** the backend returns `status = PENDING`

#### Scenario: Native result is final
- **WHEN** Alibaba Cloud has produced a final result for the submitted `certifyId`
- **THEN** the backend returns `APPROVED`, `REJECTED`, or `ERROR` with an appropriate message

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

