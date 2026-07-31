## Why

The iOS app currently clears only local session state when a user logs out, so the backend token blacklist is not engaged, and the backend soft-delete account capability has no user-facing flow. Authentication rate limits are also surfaced only as generic errors, leaving users without an accurate retry path.

## What Changes

- Make normal logout call `POST /api/auth/logout` before clearing the local session and disconnecting WebSocket; if revocation cannot be confirmed, offer retry or an explicitly warned local-only sign-out.
- Validate restored sessions through `GET /api/auth/me` so blacklisted, deleted, or expired sessions do not enter an authenticated app route while valid first-login sessions with no selected role resume at role selection without a role WebSocket.
- Add an accessible, destructive account-deletion flow backed by `DELETE /api/users/{id}`, with explicit consequences, active-order safeguards, and local data cleanup only after server confirmation.
- Add stable handling for authentication, registration, and general rate-limit responses, including a server-provided retry interval when available.
- Preserve phone verification login, first-login account creation, role selection, and role-issued replacement tokens.
- Keep virtual-number calling, CS authentication, CS lockout UI, and administrator account management out of the native user app.

## Capabilities

### New Capabilities

- `auth-account-lifecycle`: Defines restored-session validation, server-backed logout, account deletion, local cleanup, accessibility, and rate-limit retry behavior for the native iOS app.

### Modified Capabilities

- `backend-api-contract`: Clarifies the external API behavior and unified responses required for `/api/auth/me`, `/api/auth/logout`, account deletion, and rate limiting.

## Impact

- iOS state/network/UI: `AppState`, auth models, API error models, both role settings/profile logout entry points, and shared confirmation/error presentation.
- External API contract: `docs/07-api-contract.openapi.yaml` needs explicit response schemas, authorization behavior, deletion restrictions, and rate-limit semantics.
- Security/storage: logout, confirmed local-only sign-out, and deletion must disconnect WebSocket and clear token, user ID, active role, profiles, contacts, cached notification state, and user-scoped emergency recovery metadata when present; the existing Keychain migration remains a separate launch-hardening item.
- Tests: Mock, unit/UI tests, and real-cloud probes for session restore, blacklist logout, deletion, re-registration, active-order rejection, and rate-limit copy.
