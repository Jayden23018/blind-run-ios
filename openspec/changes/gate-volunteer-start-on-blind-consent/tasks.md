# Tasks

- [x] 1.1 `ErrorCode` 加 `serviceStartTooEarly` / `blindConfirmationPending` 与文案，单测钉住。
- [x] 1.2 `AppRealtimeCoordinator` 对 `BLIND_START_CONFIRMED` 发订单无关的信号（通知本身照常播报）。
- [x] 1.3 陪跑员订单 VM：`awaitingBlindConfirmation` 状态机（409 置位 / 信号清除并重拉 / 离开 `DRIVER_ARRIVED` 复位）。
- [x] 1.4 「开始跑步」按钮上方小字在等待态换成「等待对方确认」（进 accessibilityHint）。
- [ ] 2.1 单测：409 置位、`SERVICE_START_TOO_EARLY` 不置位、信号清除、非 `DRIVER_ARRIVED` 时忽略；验红。
- [x] 2.2 `validate-error-codes` 未映射清单里这两个码消失；`openspec validate --all --strict`。
- [ ] 2.3 `build-for-testing` 编译通过；真机跑覆盖的 suite。

> 2026-10-02：1.x 已实现；2.2 `validate-error-codes` 未映射 12→10（两码已消失）、`openspec validate --all --strict` 41 passed。
> 2.3 的 `build-for-testing` 已 TEST BUILD SUCCEEDED；2.1 单测已写（`VolunteerStartConsentGateTests` 5 条）但**真机尚未执行**（iPhone 锁屏，`device-test.sh` 硬失败），所以 2.1 / 2.3 不勾。
