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
The canonical API contract MUST define `POST /api/orders/{id}/start-service` as the volunteer endpoint for starting service after arrival.

#### Scenario: Volunteer starts service
- **WHEN** a volunteer starts service for an order in `DRIVER_ARRIVED`
- **THEN** the client sends `POST /api/orders/{id}/start-service`
- **AND** the request has no body
- **AND** a successful response moves the order to `IN_PROGRESS`

#### Scenario: Service start is rejected outside arrival state
- **WHEN** a volunteer calls `POST /api/orders/{id}/start-service` for an order not in `DRIVER_ARRIVED`
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

