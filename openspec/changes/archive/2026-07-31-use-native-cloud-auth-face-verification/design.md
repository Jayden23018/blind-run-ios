## Context

The iOS client originally bundled an incomplete Alibaba Cloud FaceAuth SDK 2.3.48 subset and used it to collect `metaInfo`. After the native App SDK flow was enabled, a real-device callback returned `code = 1001` and validated subcode `I4001`, which Alibaba Cloud defines as a face-module integration error. Inspection showed that the local vendor bundle lacked mandatory face modules and resources. The app targets iOS 16+, uses SwiftUI + MVVM, and must preserve an offline Mock environment.

## Goals / Non-Goals

**Goals:**
- Launch the native Alibaba Cloud verification UI from the existing Step 3 action.
- Keep network orchestration and SDK outcome handling in the ViewModel and injected services.
- Query the backend result endpoint after SDK submission and retain current retry and identity-edit behavior.
- Make the native flow testable without invoking the SDK in unit tests or Mock mode.

**Non-Goals:**
- Adding backend implementation, H5 authentication, selfie multipart upload, or Step 2 ID-card upload.
- Logging raw JWTs, identity numbers, `metaInfo`, or `certifyId` values.
- Changing Step 1 identity rules or the training flow.

## Decisions

1. **Use an injected `CloudAuthVerifying` service.** The ViewModel receives a verifier alongside the existing metaInfo provider. The production implementation wraps `AliyunFaceAuthFacade.verify`; tests and Mock mode use deterministic implementations. This avoids SDK calls from SwiftUI views and keeps the flow unit-testable.

2. **Present from the active UIKit controller.** The production verifier resolves the foreground key window's top-most view controller on `MainActor` and supplies it as `extParams["currentCtr"]`, as required by the SDK. Failure to resolve a presenter becomes a retryable client error.

3. **Treat backend result as authoritative.** SDK codes `1000` and `2006` both mean the server may have a final result, so both trigger the existing result endpoint. Codes `1003`, `1001`, `2002`, and `2003` do not start polling and instead produce cancellation or retryable errors.

4. **Separate async states.** Network initialization, native SDK presentation, and result polling use separate state flags. The primary action is disabled whenever any phase is active, preventing duplicate one-time `certifyId` consumption.

5. **Remove the Safari contract.** A successful init requires `status = PENDING` and a non-empty `certifyId`; `certifyUrl` is removed from the DTO, maintained OpenAPI, UI state, and tests. Extra fields sent temporarily by the backend remain harmless because Swift decoding ignores them.

6. **Keep Mock fully offline.** Mock initialization returns a fixed `certifyId`, and the injected Mock verifier reports that the SDK submission completed without presenting UI. The existing Mock result endpoint then completes the flow.

7. **Capture bounded SDK diagnostics.** The verifier converts `ZIMResponse` into a Sendable snapshot containing only numeric result codes, a validated short subcode, `retMessageSub` presence/length, and the SDK version. It never retains raw reason text, extended info, business data, `certifyId`, or identity data. User-facing errors show only mapped copy and the validated subcode.

8. **Initialize once and complete once.** MetaInfo collection and verification share an idempotent SDK runtime, so `initSDK()` executes at most once per process. The callback passes through a lock-protected one-shot gate before resuming its continuation.

9. **Require fresh ID_PRO attempts from the external backend.** AidRun's release target binds the live face to the Step 1 approved identity. Every init therefore requires a new App SDK `ID_PRO` attempt with a unique `OuterOrderNo`, configured `SceneId`, JWT-derived `UserId`, `IDENTITY_CARD`, server-owned `CertName`/`CertNo`, the current MetaInfo, and `MULTI_ACTION`. This is an external behavior contract only; no backend implementation is added here.

10. **Use one checksum-verified official SDK aggregate release.** The client vendors the ID_PRO face-module subset from the official Alibaba Cloud iOS 2.3.50 aggregate ZIP whose MD5 is `ef124c58ac90e33ea3d652363cc424fb`. It does not mix binaries from 2.3.48 or independently sourced component archives. The included modules are `AliyunFaceAuthFacade`, `ToygerService`, `DTFIdentityManager`, `ToygerNative`, `BioAuthEngine`, `DTFUtility`, `VerifyNativeAbility`, `APBToygerFacade`, `faceguard`, and `APPSecuritySDK`.

11. **Copy mandatory SDK resources explicitly.** Because the vendor frameworks are static, CocoaPods copies `ToygerService.bundle`, `APBToygerFacade.bundle`, `APBToygerFacadeSuitable.bundle`, and `BioAuthEngine.bundle` into the app resources. The face model `ToygerService.bundle/toyger.face.dat` is release-critical. OCR, NFC, MultiFactor, and beauty frameworks remain excluded because the registration flow does not use them.

## Risks / Trade-offs

- **SDK cannot find a presentation controller** → Resolve only foreground active scenes and top-most presented/navigation/tab controllers; surface a clear retry message.
- **SDK callback occurs off the main thread or more than once** → Resume the async continuation once and marshal UI state updates to `MainActor`.
- **Backend response remains undocumented** → Maintain the explicit local OpenAPI schema and record backend Swagger synchronization as a required integration item.
- **One-time `certifyId` is reused after cancellation or client error** → Clear it for cancellation and non-submitted SDK failures so retry always performs a fresh init.
- **Result remains PENDING after SDK return** → Reuse bounded polling and retain the manual query action as a recovery path.
- **SDK returns generic `1001`** → Map validated subcodes such as `Z1014`, `Z1023`, `I4001`, `Z1010`, camera failures, and duplicate-flow failures while keeping raw SDK payloads out of logs and UI.
- **Backend returns an expired, reused, or wrong-product `certifyId`** → Clear the failed client value, require a new init on retry, and correlate the attempt by request time and authenticated user rather than logging the identifier on-device.
- **A required static framework or model bundle is omitted** → Treat the build as invalid before real-device testing; verify the exact module allowlist and runtime resource presence so `I4001` cannot be shipped as a packaging regression.
