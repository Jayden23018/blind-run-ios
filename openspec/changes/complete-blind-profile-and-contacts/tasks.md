## 1. Contract And Product Documentation

- [ ] 1.1 Complete, validate, and archive `make-blind-runner-flow-voice-first`, preserving its guided booking and map-as-auxiliary requirements before applying this change.
- [~] 1.2 Obtain human confirmation for identity response/status/error semantics, primary-contact atomicity, contact-limit errors, and contact-added SMS delivery presentation before starting affected client behavior.
  - Identity response/status/error semantics: **answered 2026-07-30** (`demo/docs/handoff.md:117`, option ①). `POST /api/orders` now rejects `verifyStatus != VERIFIED` with 403 `IDENTITY_NOT_VERIFIED`, checked **before** the emergency-contact gate; the contact gate moved from the generic `ORDER_PERMISSION_DENIED` to 403 `EMERGENCY_CONTACT_REQUIRED`. `POST /api/blind/verify-identity` now returns `data.verifyStatus` directly.
  - Contact-limit errors: already answered (`CONTACT_LIMIT_EXCEEDED` / `CONTACT_MINIMUM_REQUIRED` / `CONTACT_FIELD_REQUIRED`, all 400).
  - Still open: primary-contact atomicity and contact-added SMS delivery presentation. This item stays unchecked until those two are answered.
- [x] 1.3 Update `AGENTS.md`, `plan.md`, and product/scope/story/flow/page/data/architecture/accessibility/task docs to make approved blind identity and one valid primary contact explicit booking prerequisites.
  - Done 2026-07-30 alongside the client-side identity gate: `AGENTS.md` (error-code list), `docs/01`, `docs/02`, `docs/03`, `docs/04`, `docs/05`, `docs/06`, `docs/09`, `docs/10`. `plan.md` needed no change — it only covers the realtime-location/track-summary gate.
- [ ] 1.4 ~~Update `docs/07-api-contract.openapi.yaml`~~ — superseded: the API contract no longer lives in this repo (see `docs/07-api-contract-MOVED.md`). The single source is the backend repo's `docs/api_spec.yaml`, which the backend already updated on 2026-07-30 for the two new 403s and the `verify-identity` response body. Nothing to do here; do **not** edit `docs/_archive-07-api-contract.openapi.yaml.bak` (known stale/incorrect).

## 2. Models And Mock Contract

- [ ] 2.1 Add typed blind identity status/response models and stable error mappings without storing identity-card numbers outside the verification ViewModel.
- [ ] 2.2 Split AppState blind readiness into basic profile, approved identity, contact count, primary-contact, and final booking-readiness computations.
- [ ] 2.3 Extend Mock for approved/pending/rejected identity states, unverified booking rejection, one-to-five contact CRUD, masked edits, and atomic set-primary behavior.

## 3. Blind Identity Flow

- [ ] 3.1 Implement a voice-first identity-verification ViewModel with format validation, duplicate-submit protection, typed backend status refresh, retry guidance, and field clearing on submit/disappear/background.
- [ ] 3.2 Build the accessible identity screen with privacy-aware input, deliberate temporary reveal behavior, TTS/VoiceOver status, and no full identity number in logs or accessibility after submission.
- [ ] 3.3 Add guided onboarding and settings routing so returning blind users resume at the first incomplete profile, identity, or contact gate while retaining logout/settings access.

## 4. Emergency Contact Management

- [ ] 4.1 Implement a dedicated contact collection ViewModel that loads and preserves the complete server list after create, update, delete, set-primary, and recoverable conflicts.
- [ ] 4.2 Build accessible contact list and add/edit forms with 1–5 enforcement, masked unchanged phone support, relationship fields, loading/error states, and result announcements.
- [ ] 4.3 Add destructive confirmation and guards that prevent final-contact deletion and require another primary before deleting the current primary.
- [ ] 4.4 Remove single-contact overwrite behavior from the existing profile form and route contact editing to the dedicated manager.

## 5. Booking Gate Integration

- [ ] 5.1 Update home and booking ViewModels to block `POST /api/orders` unless profile, identity, primary-contact, location, start point, and appointment-time gates pass.
- [ ] 5.2 Present and speak the first actionable missing gate without changing `CreateOrderRequest` or the order state machine.

## 6. Privacy, Tests, And Validation

- [ ] 6.1 Add unit tests for identity status decoding/gating, ephemeral identity cleanup, contact limits, primary invariants, masked edits, and complete AppState list preservation.
- [ ] 6.2 Add Mock/UI accessibility tests for guided onboarding, approval/pending/rejection, all contact actions, VoiceOver order, repeat status, and booking blockers using synthetic identity data only.
- [ ] 6.3 Extend cloud probes for blind identity and all emergency-contact mutations without capturing real identity fields in screenshots or logs.
- [ ] 6.4 Run `node scripts/validate-docs.mjs` and `openspec validate complete-blind-profile-and-contacts --strict --no-interactive`.
- [ ] 6.5 Run focused unit/UI tests and the required real-device/cloud validation on `111` and `iPad Pro (2)`, with privacy review and backend availability reported separately.
