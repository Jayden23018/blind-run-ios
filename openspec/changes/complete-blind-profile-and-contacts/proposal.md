## Why

The backend supports blind-runner identity verification and one-to-five emergency contacts, but the iOS app exposes neither identity verification nor complete contact management. The product decision now makes successful blind-runner real-name verification a prerequisite for booking.

## What Changes

- **BREAKING** Require a blind-runner account to complete real-name identity verification before creating an order.
- Add a voice-first identity-verification step using `POST /api/blind/verify-identity`, without persisting or redisplaying the full identity-card number.
- Expose verification states and retry/rejection guidance through the blind-runner profile/settings flow.
- Replace the single embedded emergency-contact form with management for one to five contacts: list, add, edit, delete, and set primary.
- Require at least one contact and exactly one primary contact before booking; prevent deletion of the final contact.
- Preserve existing blind-runner profile editing, booking location, order DTOs, full post-accept phone-number behavior, and the current no-virtual-number decision.

## Capabilities

### New Capabilities

- `blind-identity-and-contact-management`: Defines mandatory blind-runner real-name verification and accessible one-to-five emergency-contact management.

### Modified Capabilities

- `formal-dispatch-service-flow`: Adds approved blind-runner identity verification and a valid primary emergency contact to the booking gate.
- `backend-api-contract`: Clarifies typed blind-identity verification/status responses and emergency-contact count and primary-contact invariants.

## Impact

- iOS UI/ViewModels/models: blind profile onboarding, settings, AppState completeness gates, identity request/status presentation, and a dedicated emergency-contact manager.
- External API contract: consume `/api/blind/verify-identity` plus contact list/create/update/delete/set-primary endpoints; document verification status and stable error responses.
- Privacy/accessibility: identity data must not be logged or persisted locally, and every verification/contact action requires VoiceOver labels, TTS feedback, masked sensitive data, and clear destructive confirmations.
- Tests: Mock and unit/UI coverage for verification gating, rejection/retry, 1–5 limits, primary contact invariants, and unchanged booking payloads.
- Sequencing: finish and archive `make-blind-runner-flow-voice-first` first; this change's modified booking-gate requirement carries forward its guided voice-first behavior while adding identity and primary-contact gates.
