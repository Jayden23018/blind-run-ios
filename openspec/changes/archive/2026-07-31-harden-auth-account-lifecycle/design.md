## Context

`AppState` currently restores a token, user ID, and active role directly from `UserDefaults`, connects WebSocket immediately, and exposes synchronous `clearSession()` as every logout action. The external backend now blacklists logged-out JWTs in Redis, exposes `GET /api/auth/me`, and soft-deletes users through `DELETE /api/users/{id}`. The OpenAPI document lists these endpoints but does not yet define sufficiently precise success, ownership, active-order, or rate-limit response schemas.

This is a frontend-only change. Backend implementation, Redis configuration, CS authentication, and administrator tooling remain outside the repository.

## Goals / Non-Goals

**Goals:**

- Make session restoration authoritative against the cloud backend before entering an authenticated route.
- Route every user logout entry through one server-backed async operation.
- Provide a safe, accessible account-deletion flow and deterministic local cleanup.
- Give users accurate rate-limit retry feedback without inventing client-only cooldowns.
- Preserve role-token replacement and existing login behavior.

**Non-Goals:**

- Keychain migration, HTTPS/domain migration, refresh tokens, multi-device session management, CS login/lockout screens, administrator user management, and virtual-number calling.
- Any backend implementation or a locally runnable server.

## Decisions

### 1. Add an explicit session-restoration phase

`AppState` will expose a restoration state such as `restoring`, `choosingRole`, `authenticated`, or `unauthenticated`. A stored token will be validated with `GET /api/auth/me` before profile routing or WebSocket connection. A successful response always hydrates a typed `currentUser` and `userId`. A valid `BLIND` or `VOLUNTEER` role then connects the corresponding WebSocket and enters the role flow; a missing or `UNSET` role remains authenticated, connects no role WebSocket, and routes to role selection. Only 401, deleted-user responses, or unsupported/malformed role data clear the local session and route to login.

Alternative considered: keep optimistic restoration and wait for the first feature API to fail. This briefly exposes authenticated screens for revoked tokens and creates inconsistent cleanup paths.

### 2. Centralize destructive session operations in AppState

All blind-runner, volunteer, onboarding, and settings logout buttons will call one async `logout()` operation. `POST /api/auth/logout` success, or a 401 indicating that the token is already invalid, will disconnect WebSocket and invoke a single private local-cleanup routine. A network or 5xx failure initially keeps the session locally, states that server revocation was not confirmed, and offers retry or an explicitly confirmed "仅退出本机" fallback. Choosing that fallback disconnects WebSocket and clears local state while warning that the remote token may remain valid; it never claims that the backend token was revoked.

Alternative considered: always clear locally in a `defer`. That can silently lose the blacklist guarantee. An explicit fallback preserves user control on a shared or offline device while accurately distinguishing local sign-out from server revocation.

### 3. Require server confirmation before account deletion cleanup

Account deletion will be available from both role settings surfaces and will use two explicit confirmation stages. Before enabling final confirmation, the client will check known active orders for clear guidance, but `DELETE /api/users/{currentUser.id}` remains authoritative. Only a successful response clears local state. The UI will never offer a local-only account deletion.

The backend must enforce that a JWT can delete only its own user ID and must define behavior for active orders. Client-side path construction is not an authorization control.

Alternative considered: expose a generic user-ID delete method. This increases misuse risk and violates the user-owned lifecycle scope.

### 4. Model rate limits as a first-class API error

`URLSessionAPIClient` will map HTTP 429 into a rate-limited error containing the backend message, bucket when provided, and retry interval. It will prefer the `Retry-After` header and fall back to a unified response field. Login/send-code controls will disable only for the authoritative interval; general actions will show retry guidance without globally freezing unrelated features.

2026-07-11 人工确认：HTTP 429 使用稳定错误码 `RATE_LIMITED`；`Retry-After` 使用整数秒；统一响应体可包含可选的 `rateLimitBucket` 与 `retryAfterSeconds`。桶标识为 `AUTH`、`REGISTRATION`、`GENERAL`。

### 5. Keep local cleanup complete and idempotent

One cleanup routine will disconnect WebSocket and clear token, user ID, current user, active role, profiles, registration status, emergency contacts, pending notifications, user-scoped emergency recovery metadata when present, and persisted equivalents. It must be safe to call after 401, successful logout, confirmed local-only sign-out, successful deletion, or startup validation failure.

## Risks / Trade-offs

- [Risk] Cloud unavailability prevents token revocation. → Keep the user on the current screen initially, offer retry, and allow a clearly warned local-only sign-out so credentials and private state need not remain on the device.
- [Risk] `/api/auth/me` adds a startup round trip. → Show an accessible restoration progress state and apply the existing short network timeout.
- [Risk] Deleting during an active order could orphan a service. → Perform a client preflight and require a backend-owned active-order rejection code before release.
- [Risk] Soft deletion may leave WebSocket connected briefly. → Disconnect only as part of the immediate success cleanup on the main actor.
- [Risk] Multiple logout buttons regress independently. → Remove direct `clearSession()` calls from views and cover all entry points with tests.

## Migration Plan

1. Confirm and document `/api/auth/me`, logout, deletion, ownership, active-order, and rate-limit response contracts.
2. Add typed current-user and rate-limit models plus Mock behavior.
3. Introduce restoration state, role-less first-login routing, centralized async session operations, and the warned local-only sign-out fallback in `AppState`.
4. Replace all direct view-level session clearing with shared ViewModel actions and confirmations.
5. Add account-deletion UI, local cleanup, and tests.
6. Run documentation/OpenSpec validation, focused tests, both real-device baselines, and cloud blacklist/re-registration probes.

Rollback can hide account deletion and return routing to stored-session behavior, but server-backed logout should remain once validated because it closes a security gap.

## Confirmed Contract Decisions

- 2026-07-11 人工确认：账户删除的阻断状态为 `PENDING_MATCH`、`PENDING_ACCEPT`、`DRIVER_EN_ROUTE`、`DRIVER_ARRIVED`、`IN_PROGRESS`、`REMATCHING`，稳定错误码为 `ACTIVE_ORDER_ACCOUNT_DELETION_BLOCKED`。
- 2026-07-11 人工确认：软删除成功后，该账户的所有有效 Token 均失效，而非仅当前请求携带的 Token。
- 2026-07-11 人工确认：HTTP 429 使用 `RATE_LIMITED`；`Retry-After` 为整数秒；响应体可包含 `retryAfterSeconds` 与 `rateLimitBucket`；桶标识为 `AUTH`、`REGISTRATION`、`GENERAL`。
