# Tasks

- [x] 1.1 `PrivacyConsentPurpose` 新增 `launchSummary`（仅 `.appLaunch`）与 `launchSpokenScript`；单测钉住摘要点名关键词。
- [x] 1.2 `PrivacyConsentGateView` 重排：摘要 + 入口卡片 + 常驻底部操作栏；辅助功能字号下操作栏内联。
- [x] 1.3 完整清单走 `LegalFallbackDocumentView`，6 条 `disclosures` 原文不动。
- [x] 2.1 `PrivacyConsentTests` 全绿（含指纹用例：`disclosures` 未变所以指纹不变）。
- [x] 2.2 `xcodebuild build-for-testing` 编译通过。
- [ ] 2.3 真机跑 `testFirstLaunchBlocksTheLoginScreenUntilTheDisclosureIsAccepted`，并在默认字号与 AX5 各截一张图自评。
- [ ] 2.4 真机开 VoiceOver 走一遍：摘要 → 入口 → 底部按钮的遍历顺序、拒绝说明是否被念出。

> 2026-10-01：2.1 真机单测 `PrivacyConsentTests` + `LegalLinksTests` → passed=28 failed=0（iPhone 16 Pro，含新增两条）。
> 2.3 / 2.4 未做：两台真机均 `transportType: localNetwork`，UI runner 报 code 74（记忆 `ui-test-runner-needs-usb-not-wifi`，非代码问题）。插 USB 后补。
