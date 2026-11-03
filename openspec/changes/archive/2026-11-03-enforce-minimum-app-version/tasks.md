# Tasks

- [x] 1.1 `AppVersionResponse` 与 `AuthServing.appVersionRequirements()`，`requiresAuth: false`。
- [x] 1.2 `AppVersionNumber` 逐段按数字比较，解析不了返回 nil。
- [x] 1.3 `AppUpdatePolicy`：版本判定与呈现判定两个纯函数，失败一律不弹。
- [x] 1.4 `AppUpdateGate`：串行检查，「稍后」按版本持久化，必须更新不记录。
- [x] 1.5 `AppState.appUpdateOrderPresence()`：判据是 `isEscortUnderway`，查不到算 unknown。
- [x] 2.1 系统 `.alert`：必须更新只有「去更新」，可关闭的有「稍后」「去更新」。
- [x] 2.2 根视图接线：启动、登录状态变化、陪跑结束、`scenePhase == .active`。
- [x] 3.1 单测：相等、低一位、1.10 大于 1.9、字段缺失、请求失败、进行中不弹、结束后弹、回到 App 再弹。
- [x] 3.2 `xcodebuild build-for-testing` 编译通过。
- [x] 3.3 真机跑 `AppUpdatePolicyTests`、`AppUpdateGateTests` 和 3 条 UI 用例，贴 `passed=N failed=0`。

> 2026-11-03 iPhone 16 Pro（iOS 27.0.1）：`AppUpdatePolicyTests` 22 条、`AppUpdateGateTests` 14 条、3 条 UI 用例，passed=39 failed=0。
