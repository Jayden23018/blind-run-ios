## 1. Contract And Product Documentation

- [x] 1.1 Complete, validate, and archive `make-blind-runner-flow-voice-first`, preserving its guided booking and map-as-auxiliary requirements before applying this change.
  - Done: archived as `openspec/changes/archive/2026-07-11-make-blind-runner-flow-voice-first`; its requirements live on in `openspec/specs/blind-runner-voice-first-experience/spec.md`.
- [~] 1.2 Obtain human confirmation for identity response/status/error semantics, primary-contact atomicity, contact-limit errors, and contact-added SMS delivery presentation before starting affected client behavior.
  - Identity response/status/error semantics: **answered 2026-07-30** (`demo/docs/handoff.md:117`, option ①). `POST /api/orders` now rejects `verifyStatus != VERIFIED` with 403 `IDENTITY_NOT_VERIFIED`, checked **before** the emergency-contact gate; the contact gate moved from the generic `ORDER_PERMISSION_DENIED` to 403 `EMERGENCY_CONTACT_REQUIRED`. `POST /api/blind/verify-identity` now returns `data.verifyStatus` directly.
  - Contact-limit errors: already answered (`CONTACT_LIMIT_EXCEEDED` / `CONTACT_MINIMUM_REQUIRED` / `CONTACT_FIELD_REQUIRED`, all 400).
  - Still open: primary-contact atomicity and contact-added SMS delivery presentation. This item stays unchecked until those two are answered.
- [x] 1.3 Update `AGENTS.md`, `plan.md`, and product/scope/story/flow/page/data/architecture/accessibility/task docs to make approved blind identity and one valid primary contact explicit booking prerequisites.
  - Done 2026-07-30 alongside the client-side identity gate: `AGENTS.md` (error-code list), `docs/01`, `docs/02`, `docs/03`, `docs/04`, `docs/05`, `docs/06`, `docs/09`, `docs/10`. `plan.md` needed no change — it only covers the realtime-location/track-summary gate.
- [-] 1.4 **作废 / 无需执行**（不是未完成项）。~~Update `docs/07-api-contract.openapi.yaml`~~ — superseded: the API contract no longer lives in this repo (see `docs/07-api-contract-MOVED.md`). The single source is the backend repo's `docs/api_spec.yaml`, which the backend already updated on 2026-07-30 for the two new 403s and the `verify-identity` response body. Nothing to do here; do **not** edit `docs/_archive-07-api-contract.openapi.yaml.bak` (known stale/incorrect).

## 2. Models And Mock Contract

- [x] 2.1 Add typed blind identity status/response models and stable error mappings without storing identity-card numbers outside the verification ViewModel.
  - `blindRun/Core/Models/ProfileModels.swift`：`BlindVerifyStatus`（`NOT_VERIFIED` / `VERIFIED` / `FAILED` / `unknown`，明确无 PENDING 态）、`BlindProfileResponse.identityStatus`、`VerifyIdentityResponse.resolvedStatus`（`verifyStatus` 缺省时回退 `GET /api/blind/profile`）。身份证号只作为请求 DTO 字段和 `BlindIdentityVerificationViewModel` 的 `@Published`，不进 `AppState`。
- [x] 2.2 Split AppState blind readiness into basic profile, approved identity, contact count, primary-contact, and final booking-readiness computations.
  - `blindRun/Core/AppState.swift:209-238`：`emergencyContactCount` / `singlePrimary` / `hasValidEmergencyContacts` / `isBlindIdentityVerified` / `isBlindBasicProfileComplete` / 汇总的 booking readiness + `BlindBookingGate.firstMissing` 调用。
- [x] 2.3 Extend Mock for approved/pending/rejected identity states, unverified booking rejection, one-to-five contact CRUD, masked edits, and atomic set-primary behavior.
  - `blindRun/Core/MockAPIClient.swift`：`:240` verify-identity、`:856` `CONTACT_LIMIT_EXCEEDED`、`:918` set-primary（返回 `{"success": true}`，强制客户端重新 GET）、`:931` `CONTACT_MINIMUM_REQUIRED`、`:1010-1033` 下单 403 顺序（`APPOINTMENT_TOO_SOON` → `IDENTITY_NOT_VERIFIED` → `EMERGENCY_CONTACT_REQUIRED`）。注意后端没有 PENDING 态，Mock 只覆盖 `VERIFIED` / `NOT_VERIFIED` / `FAILED`。

## 3. Blind Identity Flow

- [x] 3.1 Implement a voice-first identity-verification ViewModel with format validation, duplicate-submit protection, typed backend status refresh, retry guidance, and field clearing on submit/disappear/background.
  - `blindRun/Profile/BlindIdentityVerificationView.swift:28-230`：`isSubmitting` 去重、`isNameValid` / `isIdCardNumberValid` 格式校验、`clearSensitiveFields()` 在提交后 / `onDisappear` / 后台通知（`:48`）三处触发。
- [x] 3.2 Build the accessible identity screen with privacy-aware input, deliberate temporary reveal behavior, TTS/VoiceOver status, and no full identity number in logs or accessibility after submission.
  - 同文件 `:260-400`：`isRevealingNumber` 临时显示、逐项 `accessibilityLabel`、`speechService.speak(statusAnnouncement)`、「重复当前状态」按钮。
- [x] 3.3 Add guided onboarding and settings routing so returning blind users resume at the first incomplete profile, identity, or contact gate while retaining logout/settings access.
  - `blindRun/BlindRunner/BlindRunnerOnboardingView.swift`：按 `basicProfile` → `identityPrompt` → `emergencyContacts` 顺序落到第一个未完成项，带 accessibilityIdentifier；退出登录统一收在 `BlindRunnerSettingsView`。

## 4. Emergency Contact Management

- [x] 4.1 Implement a dedicated contact collection ViewModel that loads and preserves the complete server list after create, update, delete, set-primary, and recoverable conflicts.
  - `blindRun/Profile/EmergencyContactsView.swift:17-200`：`load/create/update/delete/setPrimary` 每次变更后重新拉取完整列表（set-primary 只返回 `{"success": true}`）。
- [x] 4.2 Build accessible contact list and add/edit forms with 1–5 enforcement, masked unchanged phone support, relationship fields, loading/error states, and result announcements.
  - 同文件 `:380-630`：列表/新增/编辑表单、`maskedPhone` 展示、可选关系字段、`EmergencyContactRules` 上下限。
- [x] 4.3 Add destructive confirmation and guards that prevent final-contact deletion and require another primary before deleting the current primary.
  - 同文件 `:77-79`（「至少需要保留 1 位紧急联系人，不能删除最后一位」+ 主联系人保护）、`:389` 删除二次确认 alert、`:397` 设为主联系人二次确认 alert。
- [x] 4.4 Remove single-contact overwrite behavior from the existing profile form and route contact editing to the dedicated manager.
  - `blindRun/Profile/ProfileModule.swift` 已无任何 `emergencyContact` 字段；联系人编辑只在 `EmergencyContactsView` 内。

## 5. Booking Gate Integration

- [x] 5.1 Update home and booking ViewModels to block `POST /api/orders` unless profile, identity, primary-contact, location, start point, and appointment-time gates pass.
  - `blindRun/BlindRunner/BlindBookingView.swift:112-135` `BlindBookingGate.firstMissing`，顺序 `basicProfile → identityVerification → emergencyContacts → locationPermission → startPoint → appointmentTime`，与服务端 `OrderCreationService` 的 403 顺序一致。
- [x] 5.2 Present and speak the first actionable missing gate without changing `CreateOrderRequest` or the order state machine.
  - 同文件 `BlindBookingGate.message` 为展示与朗读共用文案；`CreateOrderRequest` 与订单状态机未改动。

## 6. Privacy, Tests, And Validation

- [x] 6.1 Add unit tests for identity status decoding/gating, ephemeral identity cleanup, contact limits, primary invariants, masked edits, and complete AppState list preservation.
  - 5 个专属测试文件共 51 个 `func test`：`blindRunTests/BlindIdentityAndContactModelTests.swift`（17）、`BlindIdentityVerificationViewModelTests.swift`（9）、`EmergencyContactsViewModelTests.swift`（13）、`BlindBookingGateTests.swift`（6）、`BlindReadinessAppStateTests.swift`（6）。
- [ ] 6.2 Add Mock/UI accessibility tests for guided onboarding, approval/pending/rejection, all contact actions, VoiceOver order, repeat status, and booking blockers using synthetic identity data only.
  - **未完成**（2026-07-31 核查）。`blindRun/BlindRunner/BlindRunnerOnboardingView.swift` 已埋好 `blindOnboarding.basicProfile` / `blindOnboarding.identityPrompt` / `blindOnboarding.emergencyContacts` 三个 accessibilityIdentifier，但 `blindRunUITests/` 里**零处引用**。目前只有 `testCloudBackendBlindRunnerBookingSmoke` 顺带填了一次紧急联系人表单（`blindRunUITests.swift:988-989`），不构成本条要求的引导落点 / 实名三态 / 联系人全动作 / VoiceOver 顺序 / 重复状态 / 下单拦截覆盖。
- [x] 6.3 Extend cloud probes for blind identity and all emergency-contact mutations without capturing real identity fields in screenshots or logs. — `scripts/blind-identity-and-contacts-probe.mjs`（2026-07-31 从旧分支捞回，commit `951f0c2`）。身份证只用合成值 `11010119900307781X`，手机号与联系人姓名一律脱敏后才进报告，回滚只删探针自己创建的联系人。另见 `dfd2d99`：联系人号码改为从 `AIDRUN_BLIND_PROBE_CONTACT_PHONES` 取操作者自控号码，不再凭空构造（后端会给每个新建联系人发真实短信）。
  - **未完成**：`scripts/blind-identity-and-contacts-probe.mjs` 当前不在仓库里（`scripts/` 下只有 `admin-review-volunteer.mjs`、`auth-account-lifecycle-probe.mjs`、`cloud-e2e.mjs`、`device-test-safety.sh`、`dual-device-validation.sh`、`production-readiness-check.sh`、`validate-docs.mjs`、`volunteer-dispatch-readiness-probe.mjs`）。**探针捞回仓库后即可勾上**。
- [x] 6.4 Run `node scripts/validate-docs.mjs` and `openspec validate complete-blind-profile-and-contacts --strict --no-interactive`.
  - 2026-07-31 实跑：`[validate-docs] maintained docs passed`；`Change 'complete-blind-profile-and-contacts' is valid`。
- [ ] 6.5 Run focused unit/UI tests and the required real-device/cloud validation on `111` and `iPad Pro (2)`, with privacy review and backend availability reported separately.
  - **未完成**：双真机验收未做（模拟器因高德无 arm64-sim slice 不可用，真机是唯一 XCTest 通道）。
