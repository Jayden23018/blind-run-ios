## Why

后端 PR #399（blind-run-backend#348）在 `GET /api/volunteer/achievements` 新增 `totalDistanceMeters`（米，恒非 null，无数据为 0，取整成公里由客户端做）。志愿者「我」首屏原设计稿把累计里程列为「后端刻意没有」而排除，主指标是 `N 次陪跑`；后端有了之后，项目负责人要求主指标换成公里（issue #269）。

## What Changes

- `VolunteerAchievementsResponse` 新增 `totalDistanceMeters: Int64?`，缺字段照旧只是少显示，不让整页解码失败。
- 「我」首屏主指标：累计里程向下取整 ≥ 1 公里时显示 `N 公里`，下面一行次级文案「共 M 次陪跑」；否则（缺字段、不足 1 公里、2026-08-14 之前无里程快照的老订单）保持 `M 次陪跑`，不显示「0 公里」。
- VoiceOver 文案随之：有里程时念「累计陪跑 N 公里，共 M 次陪跑」，无里程时与现在逐字相同。
- 新人态（`totalCompleted` 为 0 / 缺失）不变，不看里程。
- **不改**：三列统计、星级、勋章、成就页。

## Capabilities

### New Capabilities
- `volunteer-profile-first-screen`：志愿者「我」首屏主指标的取舍规则。

### Modified Capabilities

## Impact

- `blindRun/Volunteer/VolunteerAchievements.swift`、`VolunteerProfileFirstScreen.swift`、`VolunteerProfileFirstScreenView.swift`、`blindRun/Core/MockAPIClient+Profile.swift`。
- 测试：`VolunteerAchievementsTests`、`VolunteerProfileFirstScreenTests`、`IncentiveServiceTests`（memberwise 补参）。
- 契约与生成包已含该字段，无需重新生成。
