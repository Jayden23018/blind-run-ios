## Why

视力状况与导盲犬是敏感个人信息，走单独同意（`PrivacyConsentPurpose.blindVisionProfile`）。现状有两个缺口（iOS #352，安卓 #91 已按同一方案实现，负责人 2026-10-07 同意）：

1. 拒绝时请求不带 `hasGuideDog`，服务端旧的 `true` 一直留着 —— 志愿者接单前看得到，派单也按它筛人，而用户以为自己已经不提供了。
2. 同意之后没有撤回入口（PIPL 第十五条：个人有权撤回同意）。

## What Changes

- 明确拒绝时，导盲犬显式传 `false`（视力状况照旧传 `NOT_SPECIFIED`）。
- 已同意时，视力区块下方加「撤回同意，不再提供这两项」：按下立刻收起两项并整表单保存一次（视力 `NOT_SPECIFIED` + 导盲犬 `false`）；**保存成功后**才删本机同意记录并上屏、朗读成功那一句；保存失败不删记录，提示再按一次保存（首次引导态按钮名为「完成」）；撤回待保存时重新同意则那次撤回作废；保存中不能打开同意页。文案与安卓逐字一致。
- `docs/ui/android-migration-guide.md` §9「接单前隐藏敏感健康信息」那条加例外说明：这两项经单独同意后接单前下发（同意页已如实告知）。

## Capabilities

### New Capabilities

### Modified Capabilities
- `blind-vision-profile`: 拒绝时导盲犬显式传 `false`；新增撤回同意。

## Impact

- 代码：`blindRun/Profile/ProfileModule.swift`（view model 撤回状态、请求体、视力区块按钮与提示）、`blindRun/Core/PrivacyConsent.swift`（`PrivacyConsentStore.revokeConsent`）。
- 契约：只用既有 `PUT /api/blind/profile` 的 `visionLevel` / `hasGuideDog`，不改。
