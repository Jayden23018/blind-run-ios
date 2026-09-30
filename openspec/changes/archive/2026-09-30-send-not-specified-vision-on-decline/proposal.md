## Why

后端迁移 0056（blind-run-backend#326 / PR #399）新增视力状况取值 `NOT_SPECIFIED`（未提供），并把生产 11 个盲人档案全部回填成它。此前 iOS 对「用户拒绝提供」的表达是不带 `visionLevel` 键（协议上没有别的诚实表达），后端上线后应改成显式传。见 Jayden23018/blind-run-ios#268。

## What Changes

- `VisionLevel` 增加 `NOT_SPECIFIED`（展示名「未提供」）。
- 用户在视力状况单独同意页**明确拒绝**后，档案更新请求显式传 `visionLevel = NOT_SPECIFIED`；导盲犬字段仍缺席（契约里没有对应取值）。
- 「从没被问过」（如新设备同意记录不在）仍不带键，后端保留原值。
- 存量档案回读到 `NOT_SPECIFIED` 时资料页显示为「不填」，保存不带键。
- 志愿者侧 `NOT_SPECIFIED` 仍显示「请当面与跑者确认」，不显示「未提供」。

## Capabilities

### New Capabilities
- `blind-vision-profile`: 盲人视力状况在档案更新请求中的表达（同意 / 拒绝 / 未被问过）及志愿者侧展示。

### Modified Capabilities

## Impact

`blindRun/Core/Models/ProfileModels.swift`、`blindRun/Profile/ProfileModule.swift`、`blindRun/Core/Models/OrderDisplayHelpers.swift`、`blindRun/Volunteer/VolunteerInviteQueue.swift`；测试 `BlindEscortPreferencesTests`、`EscortNeedsTests`。无契约改动（契约源在后端 `docs/api_spec.yaml`）。
