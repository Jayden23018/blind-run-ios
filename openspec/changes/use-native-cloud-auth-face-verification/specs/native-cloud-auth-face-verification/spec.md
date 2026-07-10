## ADDED Requirements

### Requirement: iOS launches native CloudAuth verification
The iOS client MUST launch the bundled Alibaba Cloud native App SDK after Step 3 init returns `PENDING` with a non-empty `certifyId`, and MUST provide the active view controller as `currentCtr`.

#### Scenario: Native verification starts
- **WHEN** Step 3 init returns `status = PENDING` and a non-empty `certifyId`
- **THEN** the client invokes `AliyunFaceAuthFacade.verify` with that `certifyId`
- **AND** the client does not require or open a `certifyUrl`

#### Scenario: Presentation controller is unavailable
- **WHEN** the client cannot resolve an active view controller for `currentCtr`
- **THEN** the client displays a retryable SDK initialization error
- **AND** the client does not query the final result

### Requirement: SDK completion is resolved through the backend
The iOS client MUST use the Step 3 result endpoint as the authoritative result after the native SDK submits an authentication attempt.

#### Scenario: SDK reports successful submission
- **WHEN** the SDK callback code is `1000`
- **THEN** the client queries `POST /api/volunteer/registration/step3/face-verify/result`
- **AND** the client continues bounded polling while the backend returns `PENDING`

#### Scenario: SDK reports rejected or failed submission
- **WHEN** the SDK callback code is `2006`
- **THEN** the client queries the result endpoint for the authoritative rejection status and reason

#### Scenario: User cancels native verification
- **WHEN** the SDK callback code is `1003`
- **THEN** the client displays that verification was cancelled
- **AND** the client clears the one-time `certifyId` and allows a fresh init

#### Scenario: SDK reports a retryable client failure
- **WHEN** the SDK callback code is `1001`, `2002`, or `2003`
- **THEN** the client displays a specific SDK, network, or device-time message
- **AND** the client clears the one-time `certifyId` and allows a fresh init

#### Scenario: SDK reports a diagnostic subcode
- **WHEN** the SDK callback includes `retCodeSub`
- **THEN** the client accepts it only when it matches the bounded technical-subcode format
- **AND** the client maps known initialization, module, business-parameter, camera, and duplicate-flow subcodes to specific retry guidance
- **AND** the UI may show the validated subcode but never raw SDK reason, extended information, business data, `certifyId`, MetaInfo, JWT, or identity fields

### Requirement: Native SDK lifecycle is idempotent and callback-safe
The iOS client MUST initialize the Alibaba Cloud SDK at most once per process and MUST complete one verification request at most once even if the SDK invokes its callback repeatedly.

#### Scenario: MetaInfo and verification share initialization
- **WHEN** the client collects MetaInfo and then launches native verification
- **THEN** both operations use the same SDK runtime
- **AND** the underlying `initSDK()` function executes only once

#### Scenario: SDK invokes completion repeatedly
- **WHEN** the native SDK calls the same completion block more than once
- **THEN** only the first callback resumes the waiting verification task
- **AND** later callbacks are ignored

### Requirement: SDK diagnostics remain non-sensitive
The iOS client MUST limit diagnostics to SDK code, retCode, validated subcode, retMessageSub presence/length, and SDK version.

#### Scenario: Debug diagnostics are emitted
- **WHEN** a native verification callback is received in a DEBUG build
- **THEN** the diagnostic summary contains only the permitted bounded fields
- **AND** it does not contain raw `retMessageSub`, reason, extInfo, bizData, `certifyId`, MetaInfo, JWT, or identity data

### Requirement: Mock face verification remains offline
The development Mock environment MUST complete the native face-verification orchestration without invoking Alibaba Cloud SDK UI or performing network requests.

#### Scenario: Mock verification runs
- **WHEN** a user starts Step 3 in the Mock environment
- **THEN** the client uses deterministic Mock metaInfo and verifier results
- **AND** no native SDK UI or external network request is performed

### Requirement: Production CloudAuth package is complete and scoped
The iOS production target MUST use the mandatory ID_PRO face modules and runtime resources from one checksum-verified official Alibaba Cloud SDK aggregate release, and MUST NOT mix component binaries from different aggregate releases.

#### Scenario: Required face modules are packaged
- **WHEN** the application is built for a physical iOS device
- **THEN** the build links `AliyunFaceAuthFacade`, `ToygerService`, `DTFIdentityManager`, `ToygerNative`, `BioAuthEngine`, `DTFUtility`, `VerifyNativeAbility`, `APBToygerFacade`, `faceguard`, and `APPSecuritySDK`
- **AND** the app resources contain `ToygerService.bundle`, `APBToygerFacade.bundle`, `APBToygerFacadeSuitable.bundle`, and `BioAuthEngine.bundle`
- **AND** `ToygerService.bundle` contains a non-empty `toyger.face.dat`

#### Scenario: Unused identity modules remain excluded
- **WHEN** the ID_PRO-only volunteer registration target is packaged
- **THEN** OCR, NFC, MultiFactor, and beauty frameworks and resource bundles are not included
- **AND** the application does not request permissions solely for those excluded capabilities
