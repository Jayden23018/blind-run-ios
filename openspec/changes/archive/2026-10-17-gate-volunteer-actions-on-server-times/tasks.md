# Tasks

- [x] 1.1 `OrderDetailResponse` 接 `earliestDepartureAt` / `blindConfirmDeadlineAt`（`earliestServiceStartAt` 随 #334），`replacingStatus` 带过去。
- [x] 1.2 `VolunteerActionGate`：按主按钮与放行时刻推出锁 / 小字；同意闸不锁；字段缺失不锁。
- [x] 1.3 订单页接上：`isPrimaryEnabled` 与按钮上方小字（进读屏提示）。
- [x] 1.4 首页预约卡「确认我还会去」接同一道闸（只看 `SCHEDULED_CONFIRMED`）。
- [x] 2.1 单测 `VolunteerActionGateTests`；验红。
- [x] 2.2 `build-for-testing`；真机跑覆盖的 suite。
- [x] 2.3 UI 用例 `blindRunUITests.testVolunteerDepartureButtonStaysDisabledUntilTheServerReleaseTime` 真机执行并验红（10-17 iPhone：passed=1；去掉 `&& !gate.isLocked` 后红）。
