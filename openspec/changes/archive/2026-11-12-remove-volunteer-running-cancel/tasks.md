## 1. 删跑步中取消入口

- [x] 1.1 `VolunteerRunningPage` 删 `onCancel` 参数与灰字「取消订单」按钮（`volunteerRunningCancel`），更新注释
- [x] 1.2 `VolunteerInServiceView+Flow.swift` 调用点删 `onCancel`
- [x] 1.3 删 `VolunteerOrderFlowCopy.runningCancelSheet` 与 `cancelSheet(for:)` 的 `.inProgress` 分支
- [x] 1.4 订单进入 `IN_PROGRESS` 时收起取消弹层
- [x] 1.5 删 `AlertAnnouncementPriorityTests.testCancelSheetDuringTheRunWarnsAboutLeavingTheRunnerAlone`；UI 用例横屏那条改断言取消按钮不存在
- [x] 1.6 `grep` 计数：`runningCancelSheet` 为 0；`volunteerRunningCancel` 只剩 UI 用例里断言「不存在」的那条哨兵

## 2. 跑步中地图画实时轨迹

- [x] 2.1 `VolunteerInServiceViewModel` 存 `/track` 的 `primaryRouteCoordinates`（离开 `IN_PROGRESS` 清空，失败不清）
- [x] 2.2 `trackingMapInput` 非完成态传它

## 3. 验证

- [x] 3.1 编译门禁 `build-for-testing`（负责人 11-05 定不跑真机测试；单测与 UI 用例已改未运行）
