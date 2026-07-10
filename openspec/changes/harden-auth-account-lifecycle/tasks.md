## 1. Contract And Documentation

- [ ] 1.1 Obtain human confirmation for account-deletion blocking statuses/error code, token invalidation scope after deletion, and 429 code/header/body fields before starting affected client behavior.
- [ ] 1.2 Update `docs/07-api-contract.openapi.yaml` with typed `/api/auth/me` including absent/`UNSET` first-login role, `/api/auth/logout`, self-delete, active-order rejection, ownership, token invalidation, phone reuse, and rate-limit responses.
- [ ] 1.3 Update product, scope, flow, page, data-model, architecture, accessibility, test-account, and execution-plan docs with server-backed logout, session validation, and account deletion behavior.

## 2. Models And Network Semantics

- [ ] 2.1 Add typed current-user with optional/`UNSET` active role, logout/delete success, and rate-limit models without persisting additional sensitive data.
- [ ] 2.2 Extend `APIError` and `URLSessionAPIClient` to parse HTTP 429, `Retry-After`, unified fallback fields, and rate-limit bucket data when supplied.
- [ ] 2.3 Add Mock behavior for role-selected and role-less `/api/auth/me`, token-revoking logout, failed-revocation local-only sign-out, self-delete, active-order deletion rejection, deleted-phone re-registration, and rate limits.

## 3. Session Lifecycle

- [ ] 3.1 Add explicit session-restoration state, validate stored JWTs through `/api/auth/me`, route valid absent/`UNSET` roles to role selection without WebSocket, and connect a role WebSocket only after a valid active role exists.
- [ ] 3.2 Refactor `AppState` to own one idempotent local-cleanup routine that clears all persisted and in-memory user state, including user-scoped emergency recovery metadata when present.
- [ ] 3.3 Implement centralized async server-backed logout, treating success and 401 as cleanup conditions; on network/server failure preserve the session initially and offer retry or an explicitly confirmed local-only cleanup that does not claim revocation.
- [ ] 3.4 Replace every direct view-level `clearSession()` logout call with the centralized operation, loading state, retryable error, existing second confirmation, and the warned local-only fallback after revocation failure.

## 4. Account Deletion

- [ ] 4.1 Add shared account-deletion ViewModel state and an active-order preflight using canonical blocking statuses while keeping the backend authoritative.
- [ ] 4.2 Add accessible two-stage account-deletion UI to blind-runner and volunteer settings/profile surfaces.
- [ ] 4.3 Call `DELETE /api/users/{currentUser.id}`, perform local cleanup only after server confirmation, and preserve session state on failure.

## 5. Rate-Limit Experience

- [ ] 5.1 Apply authoritative retry countdown behavior to send-code/login/registration controls and provide TTS plus VoiceOver feedback.
- [ ] 5.2 Present general-bucket rate limits without discarding feature state or disabling unrelated operations.

## 6. Tests And Validation

- [ ] 6.1 Add unit tests for role-selected and role-less startup validation, revoked/deleted sessions, logout success/401/failure/local-only fallback, cleanup idempotence, user-scoped metadata cleanup, and rate-limit parsing/countdowns.
- [ ] 6.2 Add Mock/UI tests for role-less restoration, every logout entry, warned local-only sign-out, both account-deletion routes, duplicate-submit protection, active-order blocking, failure preservation, and accessible announcements.
- [ ] 6.3 Extend cloud contract probes to verify blacklist rejection, delete ownership, active-order behavior, soft deletion, and phone re-registration without adding backend code.
- [ ] 6.4 Run `node scripts/validate-docs.mjs` and `openspec validate harden-auth-account-lifecycle --strict --no-interactive`.
- [ ] 6.5 Run focused unit/UI tests plus the required real-device baselines on `111` and `iPad Pro (2)` and record cloud availability separately.
