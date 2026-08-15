## Why

上架前复核（`docs/review/blind-app-review-followup-20260815.md`）之外，逐条核对合规链路时发现
**这个 App 从来没有征求过任何同意**：

- 隐私政策与用户协议只在「设置 → 关于」里**可读**（`LegalDocumentsView.swift`）。入口存在不等于同意存在 ——
  这两件事在合规上是分开的。首次启动直接落到登录页，用户在读到任何说明之前就被要求输入手机号。
- 中国区上架与工信部检测把「首次运行未经同意即开始收集」列为违规项；App Store 审核 5.1.1 同样要求
  收集前取得同意。这不是「上线后再补」的事，**外部 TestFlight 的第一个构建就要过 App Review**。
- 敏感个人信息（PIPL 第 28 条）在本 App 里有三类：身份证号、人脸、行踪轨迹。第 29 条要求**单独同意**，
  一次概括的「同意隐私政策」覆盖不了它们。**三类里只有轨迹做到了**
  （`RunPlanShareConsent`，2026-08-13 合入）；两端实名认证收集身份证号（志愿者还叠一次人脸活体）
  一直是填完直接 POST。
- 内置隐私政策全文（`LegalFallbackCopy`）**漏列了身份证号、麦克风与语音内容、相机与人脸**。
  后端 `privacyPolicyUrl` 目前返回 `null`，所以**用户和审核员实际读到的就是这一份** ——
  漏列等于「未公开收集使用规则」。

## What Changes

- 首次启动加一道告知与同意门，排在**根路由之前**（登录页也在门后：手机号是个人信息）。
  同意按设备记、按告知版本失效；拒绝留在本页并说明后果，**不退出 App**。
- 两端实名认证提交前各加一道单独同意：盲人端（姓名 + 身份证号）、志愿者端（姓名 + 身份证号 + 人脸活体）。
  没有同意就不发请求。同意按**人**记。
- 内置隐私政策补齐实际收集项，并单列「敏感个人信息」一节说明「到那一步会再单独问一次」。
- 告知页的排版规则（全屏、每条告知独立 VoiceOver 焦点、拒绝与同意等大）收进一个共用组件，
  行程分享那页改为复用它 —— 三份复制品会在改一处时静默漂移。
- `Info.plist` 补 `ITSAppUsesNonExemptEncryption`，免掉每次上传构建的手工出口合规问答。

**不做**：不引入「仅浏览」模式（拒绝后 App 里没有任何不依赖账号的功能，做一个空壳只是把死路包装一层）；
不改 `restoreSession` 的启动时序（老用户已同意过，恢复会话不是新的收集行为）。

## Impact

- Affected specs: `auth-account-lifecycle`
- Affected code: `blindRun/ContentView.swift`、`blindRun/Core/AppState.swift`、
  `blindRun/Core/PrivacyConsent.swift`（新）、`blindRun/Core/PrivacyConsentGateView.swift`（新）、
  `blindRun/Shared/ConsentDisclosureView.swift`（新）、`blindRun/Shared/RunPlanShareConsentView.swift`、
  `blindRun/Profile/BlindIdentityVerificationView.swift`、
  `blindRun/Volunteer/VolunteerRegistrationFlowView.swift`、
  `blindRun/Core/Models/LegalLinksModels.swift`、`blindRun/Info.plist`
- 后端：无契约改动。**仍然阻塞在后端/运营**的是正式隐私政策与用户协议的 URL
  （`GET /api/misc/legal-links` 线上返回两个 `null`）；在那之前内置全文承担这件事。
- 发布风险：同意门是**所有用户**冷启动的第一屏，写错等于 App 打不开。UI 用例默认跳过它
  （`AIDRUN_UI_TEST_RESET_STATE` 生效时），只有 `AIDRUN_UI_TEST_FORCE_PRIVACY_CONSENT=1` 那条真的走；
  这条规则本身有单测（写反的表现是全部 UI 用例被挡住）。
