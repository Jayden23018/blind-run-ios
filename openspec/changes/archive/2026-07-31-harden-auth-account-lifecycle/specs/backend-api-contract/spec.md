## ADDED Requirements

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
