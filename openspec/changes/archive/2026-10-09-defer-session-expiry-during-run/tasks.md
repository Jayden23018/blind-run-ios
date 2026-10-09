## 1. 会话暂缓

- [x] 1.1 `AppState.handleAuthenticatedAPIError`：跑步中 401 进入暂缓，暂缓中限频补念，其余照旧登出
- [x] 1.2 结束暂缓：本单离开 `IN_PROGRESS`（本地记录与实时推送两路）、跑者退出订单页、「现在重新登录」按钮

## 2. 暂缓期间

- [x] 2.1 两端订单页停止轮询
- [x] 2.2 跑者端求助入口切本地拨号（新档 `BlindHomeSOSMode.localCallSessionExpired` + `EmergencyCallContext.runnerSessionExpired`），协调器兜底落 `.unsentSessionExpired`（两端都生效）
- [x] 2.3 `ContentView` 横幅与播报（跑者 / 陪跑员两套文案）

## 3. 验证

- [x] 3.1 单测：跑步中 401 不清会话、非跑步中照旧登出、限频补念、结束时机、停轮询、求助兜底与入口模式；UI 用例：横幅、求助中心本地拨号、离开订单页才登出；在已提交的基线上验红
- [x] 3.2 编译门禁通过；改了 `AppState`，真机跑全量，`passed=N failed=0`
