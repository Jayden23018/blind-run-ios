## Why

首启告知页（`PrivacyConsentGateView`）原先是整页，把 6 条完整告知摊开，同意 / 不同意按钮排在页面最底下；
项目负责人对照其他 App 指出差异（2026-10-01，issue #277）：常规形态是**覆盖在页面上的居中小弹窗**：一段简短摘要 + 《隐私政策》《用户协议》链接 +
左「不同意」右「同意」，要读全文再点进去。（第一版做成了摘要整页，被项目负责人指出「不是弹窗」，已改。）

对盲人用户同样成立：打开 App 先听 6 条再找按钮，不如先听一段摘要、按钮随时可达，
需要细节再进二级页逐条听。

## What Changes

- 首启告知改为**居中卡片弹窗**（与常规 App 一致），不是整页：压暗的背景（只有品牌底板，**不渲染登录页**）+
  标题「个人信息保护提示」+ 一段摘要 + 《隐私政策》《用户协议》/ 完整收集清单 / 再听一遍 + **左「先不同意」右「同意并开始使用」**。
- 两个按钮同样大。常规字号左右并排；辅助功能字号（`isAccessibilitySize`）退回竖排。整张卡内容一起可滚，卡高封顶屏高 85%。
- 弹窗标 `isModal`、背景对读屏隐藏；所有可点控件 ≥ 64pt（盲人端触达下限，守卫 `small-touch-target`），入口两两并排成两行以免把弹窗撑成整页。
- 7 条完整告知**原文保留**，放进「完整收集清单」二级页（复用 `LegalFallbackDocumentView`，每条仍是独立 VoiceOver 焦点）。
- 首启自动播报改为「弹窗标题 + 摘要」，不再念 7 条全文；「再听一遍」同。

**不做**：不改 `disclosures` 文案、不升 `disclosureVersion`（处理行为没变，只是呈现换了位置；
判据见 `PrivacyConsent.swift` 里 `disclosureVersion` 的注释）；不动 `ConsentDisclosureView`
（行程分享、两端实名认证共用，那三处是收集点的**单独同意**，仍要逐条摊开）。

## Impact

- `blindRun/Core/PrivacyConsentGateView.swift`（重排）、`blindRun/Core/PrivacyConsent.swift`（新增 `launchSummary`）。
- 保留全部既有 accessibility identifier（`appLaunchConsent*`），UI 用例 `testFirstLaunchBlocksTheLoginScreenUntilTheDisclosureIsAccepted` 不改。
- `disclosures` 此前已随跑后运动记录升到告知版本 2（7 条），本变更在其之上只改呈现，指纹与版本不变。
