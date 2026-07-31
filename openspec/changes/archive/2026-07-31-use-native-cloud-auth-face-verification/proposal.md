## Why

The volunteer face-verification flow currently mixes Alibaba Cloud's native App SDK initialization with an H5 `certifyUrl` presentation flow. The cloud backend now returns the native SDK's `certifyId`, so the iOS client must invoke `AliyunFaceAuthFacade.verify` directly instead of treating the missing URL as an error.

## What Changes

- Replace the Safari-based face-verification handoff with the bundled Alibaba Cloud native iOS SDK.
- Accept `PENDING` init responses containing a non-empty `certifyId` without requiring `certifyUrl`.
- Map native SDK completion codes to server result polling, retry, cancellation, and user-facing errors.
- Preserve only non-sensitive SDK diagnostics (`code`, `retCode`, validated `retCodeSub`, message presence/length, and SDK version) so `1001` failures can be routed without exposing registration data.
- Initialize the SDK through one shared idempotent runtime and protect the asynchronous callback from duplicate completion.
- Keep Mock registration offline by injecting a deterministic face-verification service.
- Update the maintained API and product documents to remove `certifyUrl` from the native App SDK flow.
- Record the external backend requirement to issue a fresh `ID_PRO` App SDK `certifyId` for every attempt using the Step 1 approved identity data.
- Replace the incomplete Alibaba Cloud 2.3.48 vendor bundle after the native callback identified `I4001`, and integrate the complete ID_PRO face-module subset from the checksum-verified official 2.3.50 aggregate package.

## Capabilities

### New Capabilities
- `native-cloud-auth-face-verification`: Defines the native iOS SDK launch, completion handling, retry behavior, and final result polling for volunteer registration.

### Modified Capabilities
- `backend-api-contract`: Defines Step 3 init as a JWT-authenticated `{metaInfo}` request whose successful response contains `status = PENDING` and a non-empty `certifyId`, without requiring `certifyUrl`.

## Impact

- Affects the volunteer registration ViewModel, face-verification DTOs, Mock behavior, and unit tests.
- Removes the Step 3 Safari presentation path while retaining the existing REST init/result endpoints.
- Requires the external backend to publish the concrete Step 3 init response schema; no backend source code is added to this repository.
- Requires human confirmation that the external backend uses a unique `OuterOrderNo`, the configured `SceneId`, and a fresh single-use `ID_PRO` `certifyId` for each Step 3 init.
- Updates `docs/05-page-specs.md`, `docs/06-data-model.md`, and `docs/07-api-contract.openapi.yaml`.
- Updates the local CocoaPods vendor dependency and iOS architecture documentation; the Step 3 HTTP contract remains unchanged.
