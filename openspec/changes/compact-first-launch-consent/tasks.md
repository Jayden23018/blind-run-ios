# Tasks

- [x] 1.1 `PrivacyConsentPurpose` 新增 `launchSummary`（仅 `.appLaunch`）与 `launchSpokenScript`；单测钉住摘要点名关键词。
- [x] 1.2 `PrivacyConsentGateView` 重排：摘要 + 入口卡片 + 常驻底部操作栏；辅助功能字号下操作栏内联。
- [x] 1.3 完整清单走 `LegalFallbackDocumentView`，6 条 `disclosures` 原文不动。
- [x] 2.1 `PrivacyConsentTests` 全绿（含指纹用例：`disclosures` 未变所以指纹不变）。
- [x] 2.2 `xcodebuild build-for-testing` 编译通过。
- [x] 2.3 真机跑 `testFirstLaunchBlocksTheLoginScreenUntilTheDisclosureIsAccepted`，并在默认字号与 AX5 各截一张图自评。
- [ ] 2.4 真机开 VoiceOver 走一遍：摘要 → 入口 → 底部按钮的遍历顺序、拒绝说明是否被念出。

> 2026-10-01：2.1 真机单测 `PrivacyConsentTests` + `LegalLinksTests` → passed=28 failed=0（iPhone 16 Pro，含新增两条）。
> 2.3 真机（USB，重启 iPhone 清掉陈旧 DTServiceHub 后）：`testFirstLaunchBlocksTheLoginScreenUntilTheDisclosureIsAccepted` passed=1；
> 新增 `testFirstLaunchDecisionButtonsAreReachableWithoutScrolling`（同意/不同意 `isHittable`，另留默认与 AX5 两张截图）passed=1。
> 截图为 Mock 调试构建（顶部黄色横幅是调试叠层，非生产形态）。
> 2.4 VoiceOver 遍历需人在真机上走一遍，未做。

> 2026-10-01 第二版（弹窗形态）：真机 `PrivacyConsentTests` + 两条首启 UI 用例 passed=17 failed=0；
> UI 用例新增断言：弹窗高度 < 屏高 80%、宽度 < 屏宽、不同意在左同意在右。截图（Mock 调试构建）：默认字号为居中卡片，AX5 下卡片封顶在屏内、卡内滚动。
