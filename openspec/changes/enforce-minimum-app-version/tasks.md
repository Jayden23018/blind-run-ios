# Tasks

- [x] 1.1 `AppVersionResponse` 与 `AuthServing.appVersionRequirements()`，`requiresAuth: false`。
- [x] 1.2 `AppVersionNumber` 逐段按数字比较，解析不了返回 nil。
- [x] 1.3 `AppUpdatePolicy`：版本判定与呈现判定两个纯函数，失败一律不拦。
- [x] 1.4 `AppUpdateGate`：串行检查，关闭记录按版本持久化。
- [x] 1.5 `AppState.appUpdateOrderPresence()`：本地事实优先，查不到算 unknown。
- [x] 2.1 强制更新页：64pt、可听原因、背后退出读屏树、本地拨号、Magic Tap。
- [x] 2.2 可关闭提示：同意隐私之后才弹。
- [x] 2.3 根视图接线：启动、登录状态变化、`scenePhase == .active`。
- [x] 3.1 单测：相等、低一位、1.10 大于 1.9、字段缺失、请求失败。
- [x] 3.2 `xcodebuild build-for-testing` 编译通过。
- [x] 3.3 真机跑 `AppUpdatePolicyTests`、`AppUpdateGateTests` 和 4 条 UI 用例，贴 `passed=N failed=0`。
- [ ] 3.4 真机开 VoiceOver 走一遍强制更新页：焦点落点、遍历顺序、拨号弹窗。

> 2026-11-03 iPhone 16 Pro（iOS 27.0.1）：第一轮 passed=42 failed=1，红的是
> `testAppUpdateGateCoversHomeAndOnlyOffersLocalDial`（标签栏还在读屏树里）。修隐藏器后重跑 passed=4 failed=0，
> 含这条、审计 `testAppUpdateRequiredGatePassesAudit`、用到隐藏器的 `testSessionLifecycleOverlayHidesTheScreenBehindItFromAccessibility`。
> 3.4 要人在真机上开 VoiceOver 走，含 Magic Tap（XCUITest 触发不了），未做。
