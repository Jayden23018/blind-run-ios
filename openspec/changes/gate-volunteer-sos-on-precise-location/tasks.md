## 1. 取坐标

- [x] 1.1 `EmergencyCoordinator.freshEmergencyCoordinateAskingForPrecision`：精确位置关着时先申请一次临时精确位置（`escortRun`），最多等 15 秒，再走 `freshEmergencyCoordinate`
- [x] 1.2 陪跑员两处求助入口改用它；失败原因改用 `EmergencyCoordinator.locationFailureReason`

## 2. 降级

- [x] 2.1 `EmergencySOSState.isDefinitelyUnsent`（只认 `unsentNoLocation` / `unsentSessionExpired`）
- [x] 2.2 `EmergencyCallContext.volunteerCloudUnsent` 与读屏提示；两处入口在确定没发出去时弹本地拨号

## 3. 验证

- [x] 3.1 单测 `VolunteerEmergencyPreciseLocationTests`（问一次后不发 / 允许后发出 / 开着不问 / 没同意不问 / 判定真值表 / 弹窗文案），编译门禁通过
- [ ] 3.2 真机跑 `VolunteerEmergencyPreciseLocationTests` 与 `PreciseLocationGateTests`，`passed=N failed=0`，并对关键用例验红
