## Why

首启告知页（`PrivacyConsentGateView`）把 6 条完整告知整页摊开，同意 / 不同意按钮排在页面最底下；
项目负责人对照其他 App 指出差异（2026-10-01，issue #277）：常规形态是**一段简短摘要 + 《隐私政策》《用户协议》链接 +
同意 / 不同意按钮一眼可见**，要读全文再点进去。

对盲人用户同样成立：打开 App 先听 6 条再找按钮，不如先听一段摘要、按钮随时可达，
需要细节再进二级页逐条听。

## What Changes

- 首启页改为：标题 + 一段摘要（点名手机号 / 位置 / 语音 / 身份证号 / 人脸 / 视力状况三类以上敏感信息、
  不做广告不卖第三方、敏感项到收集时再单独问）+ 「查看完整收集清单」「隐私政策全文」「用户协议全文」「再听一遍」。
- 同意 / 先不同意**常驻在屏幕底部**，不随内容滚动；拒绝后的后果说明也在底部栏里，始终可见。
  辅助功能字号（`isAccessibilitySize`）下底部栏会吃掉大半屏，此时退回到内容末尾内联。
- 6 条完整告知**原文保留**，挪进「查看完整收集清单」二级页（复用 `LegalFallbackDocumentView`，每条仍是独立 VoiceOver 焦点）。
- 首启自动播报改为「标题 + 摘要」，不再念 6 条全文；「再听一遍」同。

**不做**：不改 `disclosures` 文案、不升 `disclosureVersion`（处理行为没变，只是呈现换了位置；
判据见 `PrivacyConsent.swift` 里 `disclosureVersion` 的注释）；不动 `ConsentDisclosureView`
（行程分享、两端实名认证共用，那三处是收集点的**单独同意**，仍要逐条摊开）。

## Impact

- `blindRun/Core/PrivacyConsentGateView.swift`（重排）、`blindRun/Core/PrivacyConsent.swift`（新增 `launchSummary`）。
- 保留全部既有 accessibility identifier（`appLaunchConsent*`），UI 用例 `testFirstLaunchBlocksTheLoginScreenUntilTheDisclosureIsAccepted` 不改。
- `disclosures` 此前已随跑后运动记录升到告知版本 2（7 条），本变更在其之上只改呈现，指纹与版本不变。
