## Context

The blind-runner profile response already contains `verifyStatus`, and the OpenAPI contract lists `POST /api/blind/verify-identity`, but the app has only an unused request model. Emergency contacts are loaded as an array, while the current profile form edits only `emergencyContacts.first` and then replaces AppState with a one-element array. The backend supports one to five contacts and a distinct set-primary operation.

The approved product direction makes identity approval mandatory before blind-runner booking. This remains a native iOS frontend integration with the external cloud service; Aliyun Id2Meta execution and contact-notification SMS remain backend-owned.

The active `make-blind-runner-flow-voice-first` change also modifies the formal blind booking gate. This change therefore depends on that change being completed and archived first, and its delta carries forward the guided start-point/time/optional-needs/review flow so later archival does not erase voice-first behavior.

## Goals / Non-Goals

**Goals:**

- Add a voice-first, privacy-conscious identity-verification step and status presentation.
- Make approved identity, a complete profile, and a valid primary emergency contact explicit booking gates.
- Support one-to-five contact CRUD without losing server-returned contacts.
- Preserve current booking, map, order, phone-number, and role behavior.

**Non-Goals:**

- Storing identity-card images or numbers, implementing Id2Meta, creating an administrator review screen, adding virtual numbers, or changing order payloads.
- Enabling SOS; the separate `enable-independent-sos-safely` change owns that workflow.

## Decisions

### 1. Model blind onboarding as independent completion gates

`AppState` will distinguish basic profile completion, identity approval, and emergency-contact readiness rather than overloading the existing name-plus-any-contact boolean. Blind users can always reach profile, identity, contact management, settings, and logout; booking and order creation remain blocked until all required gates pass.

The guided onboarding order will be basic profile, identity verification, then emergency contacts, while returning users resume at the first incomplete gate.

Alternative considered: place all fields in the current profile form. Mixing identity data and multiple contacts into one submission creates partial-success ambiguity and increases accidental sensitive-data retention.

### 2. Treat backend verification status as authoritative

Identity submission sends `idCardName` and `idCardNumber` only to `POST /api/blind/verify-identity`. The client then applies a typed response or refreshes `/api/blind/profile` to resolve `NOT_SUBMITTED`, `PENDING`, `APPROVED`, or `REJECTED`. Booking unlocks only for the backend-approved value.

`需要人工确认`: the backend team must confirm exact status values, whether Id2Meta is synchronous, the response schema, and stable rejection/error codes. The UI must not invent approval from HTTP 200 alone.

Alternative considered: set local approval after a successful HTTP status. This can bypass a pending or rejected backend result.

### 3. Keep identity data ephemeral

The full identity-card number will exist only in ViewModel memory during entry/submission. It will not enter `AppState`, UserDefaults, logs, analytics, TTS, accessibility values after submission, screenshots created by tests, or generic error messages. After submission, backgrounding, or leaving the flow, the number is cleared. The UI may provide a deliberate temporary reveal control during entry but defaults to privacy-aware presentation.

Alternative considered: persist a draft to improve resume behavior. The privacy cost is disproportionate; users can re-enter the number after an interrupted submission.

### 4. Use a dedicated contact collection ViewModel

A contact manager will load the full list, expose per-row add/edit/delete/set-primary actions, and replace AppState only with the latest complete server list. Add is disabled at five contacts. Delete is disabled at one contact. A primary contact cannot be deleted until another contact is explicitly made primary.

Masked phone values returned by the backend may remain unchanged during edits by omitting the phone field; new or changed numbers must be validated as 11-digit mainland mobile numbers.

Alternative considered: let the backend silently select a new primary after deletion. Explicit primary selection gives blind users predictable safety behavior.

### 5. Keep identity and contacts out of order DTOs

Order creation continues using the existing request model. The client gate prevents submission, and the backend remains responsible for validating identity and contact prerequisites and returning stable errors if stale client state attempts booking.

## Risks / Trade-offs

- [Risk] Mandatory verification can block existing blind users at launch. → Resume them at a clear identity step while preserving profile/contact access and spoken guidance.
- [Risk] Backend status names differ from the proposed values. → Confirm and document the response before implementing status decoding.
- [Risk] Partial contact mutations leave stale AppState. → Refetch the complete list after every successful mutation and after recoverable conflicts.
- [Risk] Identity input appears in UI test artifacts. → Use synthetic IDs only in Mock tests and prohibit real-cloud screenshot capture of the field.
- [Risk] Requiring an explicit primary change adds a step. → Announce the reason and provide a direct “设为主联系人” action.

## Migration Plan

1. Complete, validate, and archive `make-blind-runner-flow-voice-first`.
2. Confirm identity response/status/error semantics and contact invariants with the backend team.
3. Update canonical docs/OpenAPI and formal booking requirements.
4. Add typed status models, Mock behavior, and separate completeness computations.
5. Implement voice-first identity and contact-management ViewModels and views.
6. Wire onboarding/settings routing and booking guards without changing order DTOs.
7. Add privacy/accessibility tests and run real-cloud verification/contact probes plus required validation.

Rollback can temporarily remove the mandatory client gate while retaining server status display and contact CRUD. Identity data has no local migration because it is never persisted.

## Open Questions

- `需要人工确认`: What are the exact identity verification response fields, status enum, and rejection/error codes?
- `需要人工确认`: Does the backend guarantee exactly one primary contact after every successful mutation, and does setting a new primary atomically clear the previous primary?
- `需要人工确认`: Does creating a contact trigger SMS synchronously or asynchronously, and should iOS display delivery status or only contact-save success?
