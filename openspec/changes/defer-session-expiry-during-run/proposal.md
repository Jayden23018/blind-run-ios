## Why

任何接口返回 401，App 都会立刻清空登录状态、退回登录页，跑步中也一样。后端 JWT 只有 24 小时有效期且没有续期
（Jayden23018/blind-run-backend#642），盲人订单页每 5 秒轮询一次订单，所以跑步途中过期是现实场景：
盲人在跑道上被踢回登录页，WebSocket 断开，云端求助不可用，还要重新收短信、输验证码（Jayden23018/blind-run-ios#376，上线前审计 M2 客户端部分）。

## What Changes

- 本账号的订单处于 `IN_PROGRESS` 时收到 401：**不**清会话、不退回登录页，进入「登录过期、暂缓退出」状态。
  非 `IN_PROGRESS` 时照旧登出。
- 暂缓期间：
  - 停掉两端订单页的 5 秒轮询（拿着过期凭证轮询只会每 5 秒再收一次 401）。
  - 云端求助不再发起：跑者端求助入口直接切到本地拨号（主紧急联系人 / 120 / 110），文案说清「App 不会代你发送求助」；
    求助协调器另设兜底（两端都生效），任何云端触发都落到「求助未发出：登录已过期，App 不会代你发送求助。请直接拨打120或110。」。
    陪跑员跑步中的求助面板没有本地拨号，本次只靠这道兜底（改面板会与在途 PR #370 冲突），列为后续项。
  - 跑步页固定底栏里的提示（不遮挡求助入口）可见、进入时播报一次：跑者端「登录已过期，跑完后需要重新登录」；陪跑员端说明结束陪跑要先重新登录。
    横幅带「现在重新登录」按钮。之后再收到 401 时限频补念。
  - 已建立的 WebSocket 不主动断开（同行位置可能仍在共享）。
- 暂缓结束、按原逻辑登出的时机：本单离开 `IN_PROGRESS`（实时推送或本地订单记录任一来源）、跑者从首页导航栈退出订单页、用户点「现在重新登录」。
- 不改后端契约；续期方案见 Jayden23018/blind-run-backend#642。

## Capabilities

### New Capabilities

### Modified Capabilities
- `auth-account-lifecycle`: 新增「跑步中收到 401 暂缓退出」要求，并规定暂缓期间的求助降级与结束时机。

## Impact

- 代码：`blindRun/Core/AppState.swift`（全局会话单例）、`blindRun/Safety/EmergencyCoordinator.swift`、`blindRun/Safety/SafetyModule.swift`、
  `blindRun/ContentView.swift`、`blindRun/BlindRunner/BlindOrderStatusView.swift`、`BlindRunnerHomeView.swift`、`BlindRunnerTabView.swift`、
  `blindRun/Volunteer/VolunteerOrderV2.swift`、`VolunteerOrderFlowViews.swift`、`VolunteerOrderFlowStep.swift`。
- 测试：`blindRunTests/` 新增用例；改的是 `AppState`，按仓库规则真机跑全量。
- API / 契约：无。
- 与在途 PR #370 的重叠：只碰 `BlindOrderStatusView` 中 #370 未改的行段。
