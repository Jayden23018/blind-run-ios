## Context

- 401 的出口只有一个：49 个调用点都经 `AppState.handleAuthenticatedAPIError` → `expireSession()`。删除账户 / 登录 / 选角色那几处直接调 `expireSession`，都不在跑步中。
- 「本账号当前订单状态」全 App 只有一份：`liveEscortCoordinator.activeStatus`，两端首页与订单页都往里写。
- 实时推送的状态变化经 `realtimeCoordinator.statusUpdatePublisher` 发出（带 `fromStatus` / `toStatus`），不需要 HTTP。
- 跑者订单页在首页 `NavigationStack` 里 push（`BlindRunnerHomeView.path`）；陪跑员跑步页有 6 个入口，各用 `navigationDestination(isPresented:)`。
- 订单页上挂着求助倒计时等 `fullScreenCover`。全屏遮罩弹出时底下页面的 `onDisappear` 可能触发，**不能**用它判「离开订单页」。

## Goals / Non-Goals

**Goals:** 跑步中 401 不踢人；停掉无意义的轮询；求助只走本地拨号且不暗示已发出；可见可听地告知；跑完 / 离开 / 主动重新登录时补登出。

**Non-Goals:** 不做凭证续期（后端 #642）；不改契约；不主动断开已建立的 WebSocket；不处理冷启动（重启 App 时还没有订单记录，401 照旧登出）。

## Decisions

1. **判据集中在 `AppState.handleAuthenticatedAPIError`**：`.unauthorized` 且 `liveEscortCoordinator.activeStatus == .inProgress` → 暂缓；已在暂缓中 → 限频补念；否则照旧 `expireSession()`。
   暂缓状态 `@Published sessionExpiryDeferral: SessionExpiryDeferral?`（带角色与播报序号），清会话时归零。
2. **结束暂缓**：`AppState` 订阅 `liveEscortCoordinator.$activeStatus`（离开 `.inProgress` 即结束）与 `realtimeCoordinator.statusUpdatePublisher`
   （本单 `fromStatus == .inProgress` 且 `toStatus != .inProgress` 即结束）；`BlindRunnerHomeView` 在 `path` 不再含订单页时调 `endDeferredSessionExpiry()`；
   横幅按钮同样调它。陪跑员端没有统一的导航路径，不做「离开页面」这一条 —— 陪跑员结束陪跑本身就要先重新登录（`finish` 需要有效凭证），横幅按钮就是出口。
3. **停轮询**：两端订单页 `shouldContinuePolling` 加 `!isSessionExpiryDeferred`。
4. **求助两层**：
   - 入口：`BlindHomeSOSMode.resolve` / `VolunteerOrderSOSMode.resolve` 增加 `isSessionExpired` 参数（默认 false），为 true 时返回本地拨号；
     本地拨号弹窗新增场景 `EmergencyCallContext.sessionExpiredDuringRun`，文案不说「当前没有进行中的陪跑」，而说登录已过期、App 不会代你发送求助。
   - 兜底：`EmergencyCoordinator.blocksCloudSOSForExpiredSession`，由 `AppState` 在进入暂缓时打开；`trigger` 在资格复核之后、取定位之前检查，落到新失败态 `.unsentSessionExpired`。
5. **告知**：`ContentView` 照 `liveEscortHealthBanner` 的写法，再挂一条横幅并 `onReceive` 播报。补念限频 30 秒（`AppState.deferredExpiryReminderInterval`）。

## Risks / Trade-offs

- 暂缓期间跑者端看不到订单状态变化（轮询停了，推送也只到 HTTP 刷新那一步）→ 跑完靠推送里的状态或跑者返回首页触发登出；跑者与陪跑员在一起，陪跑员会当面告知。
- 陪跑员暂缓期间按「结束陪跑」仍会 401 → 被限频补念接住，文案明确「先点现在重新登录」。
- `AppState` 是全局单例，按仓库规则真机跑全量。
