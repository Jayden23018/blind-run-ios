# Tasks

## 1. 告知与同意的数据层

- [x] 1.1 新增 `blindRun/Core/PrivacyConsent.swift`：`PrivacyConsentPurpose`（三个目的的文案 +
      各自的 `disclosureVersion`）、`PrivacyConsentScope`（设备 / 按人）、`PrivacyConsentStore`。
      文案放在数据层而不是 View 里 —— 它是被单测钉住的合规文本，View 测不了。
- [x] 1.2 版本号进存储 key。改文案不改版本号的表现是「旧同意被当成对新内容的同意」，
      没有任何运行时症状，只能靠 `testDisclosureFingerprintIsPinnedToItsVersion` 拦。

## 2. 首次启动的同意门

- [x] 2.1 `AppState.didAcceptPrivacyConsent` + `acceptPrivacyConsent()`（唯一写入点）。
- [x] 2.2 `AppState.resolveInitialPrivacyConsent(persistence:environment:)`：在 `init` 里定初值。
      放到 `onAppear` 会让 UI 用例先看到同意页再看到它消失，断言打在那一帧上就是随机红。
- [x] 2.3 `ContentView`：同意门排在 `routedContent` 之前；路由逻辑一行未动。
- [x] 2.4 `PrivacyConsentGateView`：全屏告知 + 「再听一遍」+ 隐私政策/用户协议全文入口
      （复用 `LegalDocumentKind.destination(in:)` 的外链/内置两条分支）。
- [x] 2.5 拒绝留在本页并说明后果，不 `exit(0)`。

## 3. 两个实名收集点的单独同意

- [x] 3.1 `BlindIdentityVerificationView`：提交按钮改走 `handleSubmitTapped()`，
      没有同意先弹全屏告知；同意先落盘再发请求。
- [x] 3.2 `VolunteerRegistrationFlowView`：同上，告知里多一条人脸活体
      （下一屏就开始活体认证，不能等到那时才说）。
- [x] 3.3 同意按人记；拿不到 userId 时用恒不命中的 scope，宁可多问一次。

## 4. 复用与收口

- [x] 4.1 抽出 `ConsentDisclosureView`（全屏、每条独立焦点、拒绝与同意等大），
      `RunPlanShareConsentView` 改为复用它并**保留原有三个 accessibility identifier**。
- [x] 4.2 `LegalFallbackCopy.privacyPolicy` 补齐身份证号 / 麦克风与语音 / 相机与人脸 / 轨迹，
      新增「敏感个人信息」一节，「你的选择」补麦克风权限与删除账户的保留范围。
- [x] 4.3 `Info.plist` 补 `ITSAppUsesNonExemptEncryption = false`。

## 5. 验证

- [x] 5.1 `blindRunTests/PrivacyConsentTests`（11 条）：store 三个目的互不相干、按人隔离、
      版本失效、AppState 跨启动保留、UI 测试跳过规则的两个方向、文案逐条自查、内置隐私政策收集项齐全。
- [x] 5.2 真机单测：`PrivacyConsentTests` + `LegalLinksTests` + `RunPlanShareConsentTests`
      + `BlindIdentityVerificationViewModelTests` + `BlindIdentityAndContactModelTests`
      → 41 passed / 0 failed（2026-08-15，iPhone 16 Pro）。
- [x] 5.3 `xcodebuild build-for-testing` → `TEST BUILD SUCCEEDED`。
- [ ] 5.4 **UI 用例 `testFirstLaunchBlocksTheLoginScreenUntilTheDisclosureIsAccepted` 未执行** ——
      真机 `transportType: localNetwork`，UI runner 走双向 DTX 握手需要 USB，
      当前一律 code 74（记忆 `ui-test-runner-needs-usb-not-wifi`，不是代码问题）。插 USB 后补跑。
- [ ] 5.5 插 USB 后跑一次**全量** UI 用例，确认同意门的默认跳过没有把别的用例挡在门外。
- [ ] 5.6 真机上开 VoiceOver 走一遍同意门：每条告知是不是独立焦点、拒绝按钮找不找得到。
