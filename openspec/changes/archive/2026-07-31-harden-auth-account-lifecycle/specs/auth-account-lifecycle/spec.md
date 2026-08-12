## ADDED Requirements

### Requirement: Stored sessions are validated before authenticated routing
The iOS app SHALL validate a restored JWT with `GET /api/auth/me` before it connects an authenticated WebSocket or presents a role-specific authenticated flow.

#### Scenario: Stored session remains valid with an active role
- **WHEN** the app launches with a stored JWT and `/api/auth/me` returns the current active user with role `BLIND` or `VOLUNTEER`
- **THEN** the app SHALL hydrate `currentUser`, `userId`, and `activeRole`
- **AND** the app SHALL then connect the role-appropriate WebSocket and route to the correct profile or home flow

#### Scenario: Stored session remains valid before role selection
- **WHEN** `/api/auth/me` accepts the stored JWT but returns no active role or role `UNSET`
- **THEN** the app SHALL hydrate `currentUser` and `userId`, keep the authenticated session, and route to role selection
- **AND** the app SHALL NOT connect a blind or volunteer WebSocket until role selection returns a replacement role token

#### Scenario: Stored session is revoked or deleted
- **WHEN** `/api/auth/me` rejects the stored JWT because it is expired, blacklisted, or belongs to a deleted account
- **THEN** the app SHALL clear all local session data
- **AND** the app SHALL route to login with an accessible explanation

### Requirement: User logout revokes the backend token
Every user-facing logout action SHALL call `POST /api/auth/logout` with the current Bearer token before completing local session cleanup.

#### Scenario: Logout succeeds
- **WHEN** the user confirms logout and the backend accepts `POST /api/auth/logout`
- **THEN** the app SHALL disconnect WebSocket and clear all local session, profile, contact, and notification state
- **AND** the app SHALL return to login

#### Scenario: Token is already invalid
- **WHEN** confirmed logout receives HTTP 401 because the token is already expired or revoked
- **THEN** the app SHALL treat the session as unauthenticated
- **AND** the app SHALL complete the same local cleanup and return to login

#### Scenario: Logout cannot reach the backend
- **WHEN** confirmed logout fails because of a network or server error
- **THEN** the app SHALL NOT claim that the token was blacklisted
- **AND** the app SHALL retain the current local session while offering a retryable, spoken error and an explicitly confirmed local-only sign-out option

#### Scenario: User chooses local-only sign-out after revocation failure
- **WHEN** backend logout failed and the user explicitly confirms "仅退出本机"
- **THEN** the app SHALL disconnect WebSocket, clear all local user data, and return to login
- **AND** the app SHALL state that server-side token revocation was not confirmed and SHALL NOT claim that the remote token was blacklisted

### Requirement: Users can delete their own account safely
The iOS app SHALL provide an accessible two-stage destructive confirmation that calls `DELETE /api/users/{currentUser.id}` and SHALL clear local state only after backend confirmation.

#### Scenario: Account deletion succeeds
- **WHEN** a user without a blocking active order confirms both deletion stages and the backend confirms soft deletion
- **THEN** the app SHALL disconnect WebSocket, clear all local user data, and return to login
- **AND** the app SHALL state that the phone number can be used to register again according to backend policy

#### Scenario: Active order blocks deletion
- **WHEN** the user has an order in a backend-defined blocking status
- **THEN** the app SHALL keep the account and session intact
- **AND** the app SHALL show and speak that the active service must be resolved before deletion

#### Scenario: Account deletion fails
- **WHEN** the delete request fails or cannot be confirmed by the backend
- **THEN** the app SHALL keep local credentials and user state intact
- **AND** the app SHALL offer retry or cancellation without presenting deletion as complete

### Requirement: Rate-limit responses provide actionable retry behavior
The iOS app SHALL handle HTTP 429 separately from generic failures and SHALL use the backend-provided retry interval when available.

#### Scenario: Verification-code request is rate limited
- **WHEN** `POST /api/auth/send-code` returns HTTP 429 with a retry interval
- **THEN** the app SHALL show and speak the backend rate-limit message
- **AND** the send-code control SHALL remain disabled for the authoritative retry interval

#### Scenario: General action is rate limited
- **WHEN** an authenticated operation returns HTTP 429
- **THEN** the app SHALL preserve the current feature state
- **AND** the app SHALL show a retry time without disabling unrelated app features

### Requirement: Session lifecycle actions remain accessible and user-owned
Logout and account deletion SHALL be exposed only for the signed-in blind-runner or volunteer user and SHALL provide VoiceOver labels, hints, loading state, and error announcements.

#### Scenario: Destructive action is in progress
- **WHEN** logout or account deletion is awaiting a backend response
- **THEN** the final destructive control SHALL be disabled against duplicate submission
- **AND** assistive technology SHALL announce that the request is in progress

#### Scenario: Administrative capability is reviewed
- **WHEN** the native user app scope is inspected
- **THEN** it SHALL NOT expose CS login, administrator user deletion, or CS lockout management
