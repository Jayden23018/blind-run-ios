## Context

见 proposal.md「Why」。现状里与设计有关的几条：

- `AppState.apiClient`（`blindRun/Core/AppState+Services.swift:7`）是计算属性，每次取都新建；有 `apiClientOverride` 时直接返回它（单测注入点）。各领域 service（`auth`、`orders`、`safety`……）都以它为 transport。
- 续期与重试在 `URLSessionAPIClient.withSessionRenewal`（`blindRun/Core/APIClient.swift:303`）：到调用方手里的 `.unauthorized` 已经是「续期也救不回来」；暂时续不了抛的是别的错误，换了账号抛 `.networkError(CancellationError())`。所以 `.unauthorized` 可以直接当「会话已失效」。
- `handleAuthenticatedAPIError`（`blindRun/Core/AppState+Session.swift:213`，`@MainActor`）：非 `.unauthorized` 返回 false；暂缓中只按间隔加一次播报序号；`IN_PROGRESS` 时进入暂缓并 `blockCloudSOSForExpiredSession()`；否则 `expireSession()`。
- 登出（`AppState+SessionRevocation.swift` 的 `logOutOnServer`）走的是 `auth` → `apiClient`；补撤（`PendingSessionRevocation`）与续期本身用各自新建的 `URLSessionAPIClient`。

## Goals / Non-Goals

**Goals:**
- 会话失效的处理只在一处发生，新写的调用方不需要知道它。
- 401 → 退出 / 暂缓 能在单测里用 Mock 客户端直接验证。

**Non-Goals:**
- 不改续期、重试、`sessionChanged` 的判定。
- 不改暂缓期间的界面、播报与求助降级（已有需求）。
- 不新增 `APIError` 的 case（全仓有穷举 `switch`）。

## Decisions

1. **用包在外面的 adapter，不改 `URLSessionAPIClient` 内部。** 新类型 `SessionAwareAPIClient: APIClientProtocol`，持有被包的客户端与一个 `@MainActor` 回调 `onSessionEnded: () -> Void`（由 `AppState` 以 weak self 提供，内部调 `handleAuthenticatedAPIError(.unauthorized)`）。`request` / `upload` 照转；`requiresAuth == true` 且捕获到 `APIError.unauthorized` 时先 `await` 回调，再原样重抛。
   - 备选：在 `withSessionRenewal` 的 `.invalid` 分支里通知。否决：Mock 与 `DisabledAPIClient` 不经过它，测不到；续期器那层「不碰会话」是刻意的分层（`APIClient.swift:297`）。
2. **包的位置在 `AppState.apiClient` 的出口。** 三个分支（Mock、Disabled、URLSession）与 `apiClientOverride` 都包，单测注入的客户端同样经过 adapter——测的就是生产路径。
3. **登出不经过 adapter。** `logOutOnServer` 改用未包的客户端（`AppState` 增加一个只给登出用的未包出口）。理由：登出的 401 按既有登出需求处理，不能多弹一次「登录已过期」。
4. **幂等放在 `handleAuthenticatedAPIError` 里。** 已无会话（access 与 refresh 都已清除）且不在暂缓中时，直接返回 true，不再 `expireSession()`，不再写过期提示。暂缓中的去重沿用现有间隔判断。这样第 2 批完成之前，adapter 与旧调用方各调一次也只登出一次。
5. **调用方契约：仍然收到 `.unauthorized`。** 页面据此「停下、不显示一般失败文案」。第 2 批把 `if appState.handleAuthenticatedAPIError(error) { return }` 改成 `if case .unauthorized = error { return }`（或等价写法），删掉对会话的直接操作。
6. **求助两处**：`EmergencyCoordinator+Trigger.swift:148` 与 `+Countdown.swift:141` 收到 `.unauthorized` 时，会话已由 adapter 处理；协调器在这之后按「暂缓中被拦」的同一失败态收尾（复用漏网云端触发的文案），不再用 `error.reasonClause`。
7. **删除账户预检**：去掉 `catch APIError.unauthorized { appState.expireSession() }` 特例，改为「是 401 就停下」。

## Risks / Trade-offs

- [后台请求的 401 会让人在不知情时被登出] → 这正是现有需求（任一接口）要求的；续期已失败，会话确实结束了。用户回到前台看到登录页与提示。
- [现有单测通过 `apiClientOverride` 注入返回 401 的客户端，行为会变：此前不登出的路径现在会登出] → 第 1 批要跑全量编译并检查断言了「401 后仍有会话」的用例，按新需求改断言，逐条写进 PR。
- [`onSessionEnded` 回调跨 actor] → 回调标 `@MainActor`，adapter 在非主线程上 `await` 它；遵守记忆 unannotated-async-closure-property-crashes-on-device。
- [第 2 批改 41 个文件，与在途 PR 冲突] → 等 #868、#869、#871 合并后再做；第 1 批只动 `Core/` 与求助、删号三处。
