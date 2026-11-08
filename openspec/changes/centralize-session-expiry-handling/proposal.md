## Why

`auth-account-lifecycle` 已经要求「任一接口返回 401、续期判定登录已失效」时按会话失效处理（跑步中暂缓，否则清会话回登录页），但现在这件事要靠每个调用方自己记得调 `AppState.handleAuthenticatedAPIError`：全仓 65 处调用、41 个文件，另有 29 个发需要登录请求的文件从来不调——那里收到 401 只显示一般错误或什么都不做，漏一处没有任何东西会报错。前端全仓审查第 3 轮（#857 候选 4）把它列为要收拢的浅 module。

## What Changes

- 新增一个包在 `AppState.apiClient` 外面的 adapter `SessionAwareAPIClient`：需要登录的请求最终抛出 `.unauthorized`（续期已失败）时，先交给 `AppState.handleAuthenticatedAPIError`，再把同一个错误原样抛给调用方。真实客户端与开发期 Mock 客户端都经过它。
- `handleAuthenticatedAPIError` 被同一次失效多次调用（adapter 一次 + 旧调用方一次）时结果不变：不重复登出、不重复播报。
- 求助触发与求助撤销收到最终 401 时也走统一处理：跑步中进入暂缓（已有需求规定暂缓期间云端求助被拦、改走本地拨号），否则清会话回登录页。此前它们把 401 当一般失败。
- 删除账户的预检收到 401 时不再直接 `expireSession()`，改走统一处理（跑步中暂缓）。
- 第 2 批（同一变更内的后续任务）：把调用方里的 `handleAuthenticatedAPIError` 调用改成「是 401 就停下」，统一处理只留在 adapter 一处。
- 不变：续期与重试逻辑（`withSessionRenewal`）；登出、补撤用的独立客户端不包 adapter；不需要登录的请求不受影响；暂缓期间的界面与播报不变。

## Capabilities

### New Capabilities

（无）

### Modified Capabilities

- `auth-account-lifecycle`: 新增「会话失效由网络层统一处理，与调用方无关」一条需求，补求助触发、求助撤销、删除账户预检、此前不处理 401 的页面四类场景。

## Impact

- 代码：`blindRun/Core/AppState+Services.swift`（`apiClient` 包 adapter）、新文件 `blindRun/Core/SessionAwareAPIClient.swift`、`blindRun/Core/AppState+Session.swift`（`handleAuthenticatedAPIError` 幂等）、`blindRun/Core/AccountDeletionViewModel.swift:46`、`blindRun/Safety/EmergencyCoordinator+Trigger.swift:148`、`blindRun/Safety/EmergencyCoordinator+Countdown.swift:141`；第 2 批涉及 41 个调用方文件。
- 红线：碰认证与求助（AGENTS §6、§10 大档）。求助的变化只是「会话已失效时更早降级到本地拨号」，不改求助文案、不改 `IN_PROGRESS` 开放规则、不新增云端调用。
- 契约：不改。后端 401 / `REFRESH_TOKEN_INVALID` 语义不变。
- 依赖：第 2 批的文件与 #868、#869、#871（候选 2 后三批）重叠，等它们合并后再做。
- 安全：认证路径改动，合并前过 security-reviewer。
