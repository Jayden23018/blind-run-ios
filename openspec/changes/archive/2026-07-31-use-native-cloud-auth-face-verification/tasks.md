## 1. Contract and SDK Service

- [x] 1.1 Update the Step 3 init DTO and Mock response to use `certifyId` without `certifyUrl`
- [x] 1.2 Add an injectable native CloudAuth verifier with active-controller presentation and deterministic Mock behavior

## 2. Volunteer Registration Flow

- [x] 2.1 Replace Safari session handling with native SDK invocation and separate initialization, SDK, and polling states
- [x] 2.2 Map SDK completion codes to result polling, cancellation, and retryable user-facing errors
- [x] 2.3 Update Step 3 copy and accessibility behavior for the native SDK flow

## 3. Tests and Documentation

- [x] 3.1 Update and extend unit tests for certifyId-only init, verifier invocation, SDK outcomes, retries, and Mock isolation
- [x] 3.2 Update maintained page, data-model, and OpenAPI documents for the native SDK contract

## 4. Validation

- [x] 4.1 Run docs and strict OpenSpec validation
- [x] 4.2 Run targeted XCTest coverage on device `111`
- [x] 4.3 Run release regression on `iPad Pro (2)` and record any backend-only integration blocker

## 5. SDK 1001 Diagnostics and Lifecycle Hardening

- [x] 5.1 Add bounded SDK response diagnostics, validated subcode mapping, and non-sensitive DEBUG summaries
- [x] 5.2 Share an idempotent SDK runtime between MetaInfo and verification and protect continuation completion with a one-shot gate
- [x] 5.3 Add tests for diagnostics, subcode copy, initialization idempotence, retry behavior, and duplicate callbacks
- [x] 5.4 Document the external `ID_PRO` fresh-attempt contract and `1001` support guidance

## 6. Follow-up Validation

- [x] 6.1 Run docs and strict OpenSpec validation plus residue checks
- [x] 6.2 Run the focused CloudAuth XCTest suite on device `111`
- [x] 6.3 Run full release regression on `iPad Pro (2)` and record remaining human/backend verification

## 7. SDK I4001 Package Completeness

- [x] 7.1 Record the validated `I4001` packaging cause, official 2.3.50 module allowlist, resources, and unchanged backend contract
- [x] 7.2 Vendor the checksum-verified official 2.3.50 ID_PRO face-module subset without mixing releases
- [x] 7.3 Update CocoaPods integration, required system dependencies, copied resources, privacy manifest, and architecture documentation
- [x] 7.4 Add build-time tests for required resources and excluded optional modules
- [x] 7.5 Run pod/build, focused and dual-device XCTest, docs/OpenSpec, privacy, and sensitive-diagnostic residue validation

## 8. Review Hardening

- [x] 8.1 Preserve authoritative SDK completion codes when diagnostic subcodes are also present
- [x] 8.2 Make the OpenAPI Step 3 init response require a non-empty `certifyId` for `PENDING` and add regression coverage
- [x] 8.3 Run focused XCTest, maintained docs validation, and strict OpenSpec validation
