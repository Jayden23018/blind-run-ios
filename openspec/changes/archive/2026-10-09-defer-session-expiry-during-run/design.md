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
   （本单 —— 订单号等于 `activeOrderID` —— `fromStatus == .inProgress` 且 `toStatus != .inProgress` 即结束）。
   两条订阅都把登出放到下一拍（`Task { @MainActor }`）：回调发生在发布方调用栈中途，同步清会话会重入写同一个 `@Published`；`BlindRunnerHomeView` 在 `path` 不再含订单页时调 `endDeferredSessionExpiry()`；
   横幅按钮同样调它。陪跑员端没有统一的导航路径，不做「离开页面」这一条 —— 陪跑员结束陪跑本身就要先重新登录（`finish` 需要有效凭证），横幅按钮就是出口。
3. **停轮询**：两端订单页启动轮询时若已暂缓连第一次也不拉（全屏遮罩收起会重新 `onAppear`）；跑者 `shouldContinuePolling`、陪跑员轮询循环里同样判断后退出。
4. **求助两层**：
   - 入口（跑者端）：`BlindHomeSOSMode.resolve` 增加 `isSessionExpired` 参数（默认 false），跑步中为 true 时返回新档 `.localCallSessionExpired`。
     单独一档而不是并进 `.localCall`：那一档的每句文案（求助中心副标题、降级说明、读屏提示、拨号弹窗）都默认「陪跑还没开始」。
     拨号弹窗新增场景 `EmergencyCallContext.runnerSessionExpired`，模式到场景的映射收进 `EmergencyCallContext.runner(for:)` 一处（原先两处三元表达式，加档时会静默归错）。
   - 陪跑员端不改入口：跑步中的求助在 `VolunteerRunHelpPanel` 里，只有云端按钮。给它加本地拨号要么改面板（`VolunteerRunningCompanion.swift`，PR #370 正在大改），
     要么在关 sheet 的同时弹拨号框（SwiftUI 时序不稳，真机验不了）。本次只靠下面的兜底，失败文案直接说「请直接拨打120或110」。列为后续项。
   - 兜底：`EmergencyCoordinator.blocksCloudSOSForExpiredSession`，由 `AppState` 在进入暂缓时打开；`trigger` 在资格复核之后、取定位之前检查，落到新失败态 `.unsentSessionExpired`。
5. **告知**：播报在 `ContentView` 按 `announcementSerial` 念（首句最高档、补念普通档，限频 30 秒）。可见部分是 `SessionExpiryNotice`，放在两端跑步页**自己的固定底栏**里、按钮上方（`OrderFlowBottomActions`、`VolunteerRunningPage`），经自定义环境值拿数据。
   第一版照 `liveEscortHealthBanner` 挂在 `ContentView` 的 `safeAreaInset` 上，真机截图里**整块盖住了「求助与安全」与主按钮**：那一层与页面之间隔着 UIKit 承载的 `TabView` / `NavigationStack`，安全区内边距传不进去。
   跑步页没有返回键，所以跑步中真正的出口是提示里的「现在重新登录」（二次确认）。

## Risks / Trade-offs

- 暂缓期间跑者端看不到订单状态变化（轮询停了，推送也只到 HTTP 刷新那一步）→ 跑完靠推送里的状态或跑者返回首页触发登出；跑者与陪跑员在一起，陪跑员会当面告知。
- 陪跑员暂缓期间按「结束陪跑」仍会 401 → 被限频补念接住，文案明确「先点现在重新登录」。
- `AppState` 是全局单例，按仓库规则真机跑全量。
