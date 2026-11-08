## Context

现状（2026-11-08，`origin/main` 39e90b09 核对过的行号；报告里的行号是 c962d379 快照）：

**状态更新的路径**

- `AppRealtimeCoordinator.attach`（`blindRun/Core/AppRealtimeCoordinator.swift:201-203`）订阅 `WebSocketService.eventPublisher`，交给 `route`（`+Routing.swift:6`）。
- `route` 对 `ORDER_STATUS_CHANGED`：先按 `messageId` 去重（`:9-16`：重复的直接丢弃、**不请求刷新**；同一 `messageId` 内容不同的请求一次刷新后返回）；只有订单在 `activeOrderIDs` 里、`fromStatus` 与 `toStatus` 都能解成 `RunOrderStatus`、两者不同、且 `OrderStatusReconciler.reconcileRealtime` 判 `.applied` 时，才发 `statusUpdateSubject`（`:18-43`）；对账拒绝时请求刷新后返回（`:30`），其余情况（含发了更新、状态值未知）都在 `:45` 请求刷新。**未知状态值在这里降级**：`RunOrderStatus(rawValue:)` 解不出就只请求刷新，不发更新。
- `requestOrderRefresh`（`+Routing.swift:107-112`）把单号插进 `@Published pendingOrderRefreshIDs`；页面 `load` 的 `defer` 里调 `completeOrderRefresh` / `failOrderRefresh`（跑者 `+Loading.swift:114-120`，陪跑员 `VolunteerInServiceViewModel.swift:252-258`；实现在 `+OrderTracking.swift:71-99`），失败按 1/2/4 秒重插。陪跑员 403 `ORDER_PERMISSION_DENIED`（单被转走）没有订单也算「权威」（`:289-292`），清掉挂着的刷新。`load` 的调用方不只轮询与刷新订阅：跑者 `+Actions.swift:43,81,89,116,124,130`、`+IntroCall.swift:253,266,299,309`、`BlindRunnerFinish.swift:88`，陪跑员 `+Nudges.swift:60`、`VolunteerInServiceViewModel.swift:183`。
- `statusUpdatePublisher` 的 5 个订阅方：
  1. 跑者订单页 `BlindOrderStatusViewModel+Realtime.swift:18-31`：`apply(replacingStatus)`，`isLoading = false`，`errorMessage = nil`。
  2. 陪跑员订单页 `VolunteerInServiceViewModel.swift:141-154`：同上，但不清 `errorMessage`。
  3. 陪跑员首页 `VolunteerHomeViewModel+Realtime.swift:19-54`：更新「当前订单」，念 `speakVolunteerStatusChange`；`CANCELLED` / `REMATCHING` 用 `DispatchQueue.main.async` 推迟一拍（`:38-46`），让订单页的整句先念、通用句被去重挡掉（#462 / #477）。
  4. 跑者首页 `BlindRunnerHomeView.swift:142-148` → `applyRealtimeStatus`（`:151-`）：念 `speakBlindRunnerStatusChange(updated, text: updated.blindRunnerAnnouncement())`。
  5. `AppState.swift:362-369`：跑步中暂缓退出时，本单离开 `IN_PROGRESS` 就结束暂缓。
- 刷新订阅：跑者 `+Realtime.swift:10-16`、陪跑员 `VolunteerInServiceViewModel.swift:133-140`，都是 `$pendingOrderRefreshIDs.sink { Task { await load } }`。

**对方位置**

- 协调器 `routePeerLocation`（`+Routing.swift:197-210`）只进不退、同一主线程周期内只发最新一条；`ingestFallbackPeerLocation`（`:176-178`）只入库不发布。
- 页面各判一次新鲜度并各排一个过期任务：跑者 `+VolunteerLocation.swift:5-23`（判 `age <= peerFreshness`，记 `latestVolunteerWebSocketDate`）与 `:52-81`（`schedulePeerExpiry` / `clearPeerLocation`）；陪跑员 `+Nudges.swift:98-114`（多记 `accuracyMeters`）与 `+OrderUpdates.swift:75-95`。
- 阈值 `LiveEscortSessionCoordinator.peerFreshness = 15`（`LiveEscortSessionCoordinator.swift:55`），被 `:287`、`BlindRunnerHomeView.swift:365`、`BlindOrderStatusView.swift:214`、`VolunteerInServiceViewModel.swift:102` 引用；跑者 REST 兜底另写字面量 `15`（`+VolunteerLocation.swift:97`）。
- 跑者订单页订阅时回放一次已存的最新样本（`+Realtime.swift:38-41`）；陪跑员不回放。

**轮询**

- 跑者 `+Loading.swift:55-69`：暂缓中第一次也不拉；之后每轮先判 `shouldContinuePolling`（`:103-109`：暂缓中停；有订单且 `!status.shouldPoll` 停），再睡 5 秒、再拉。
- 陪跑员 `VolunteerInServiceViewModel.swift:220-237`：暂缓中第一次也不拉；之后睡 5 秒、拉，拉完是终态就停，暂缓中就停。
- 两端在 `startPolling` 里 `registerActiveOrder(orderId)`；换单先 `clearPeerLocation()`。`stopPolling` 取消轮询、`acceptsPeerLocations = false`、清对方位置。

**订阅的寿命**

- 陪跑员订单页的 7 个订阅在 `configure`（`VolunteerInServiceView.swift:133`）里各建一次，**一直活到 ViewModel 释放**，`stopPolling` 不断开它们；只有对方位置靠 `acceptsPeerLocations` 关掉。
- 跑者订单页每次 `configure` 先 `cancellables.removeAll()` 再重订（`+Realtime.swift:8`），同样 `stopPolling` 不断开；订单号取动态的 `activeOrderId`。`startPolling` 支持换单（`+Loading.swift:29` 的 `currentOrderId != orderId` 分支），并且重复调用会取消旧循环、立即重拉（`BlindOrderStatusView+ActionArea.swift:84`、`+MockCounterpart.swift:52` 对同一单再调靠这个）。`configure` 在每次 `onAppear` 都跑（`BlindOrderStatusView.swift:664-678`）。两端 `acceptsPeerLocations` 在 `configure` 里就置 true（跑者 `+Loading.swift:17`，陪跑员 `VolunteerInServiceViewModel.swift:124`）。
- 刷新订阅不看登录暂缓（跑者 `+Realtime.swift:12-14`，陪跑员 `VolunteerInServiceViewModel.swift:136-138`），只有轮询看。
- 活跃订单登记：两端订单页在 `startPolling` 用不带 `status:` 的 `registerActiveOrder`（`+OrderTracking.swift:6`）；`stopPolling` **不注销**，协调器有逻辑依赖这一点（`+Notifications.swift:81-82`）；注销由页面在终态做（跑者 `+Loading.swift:215`，陪跑员 `+OrderUpdates.swift:51,152`、`+Nudges.swift:48`），会连 `latestPeerSamples` 一起清。

**陪跑员订单页的其余订阅**（都在 `VolunteerInServiceViewModel.swift`）：`orderLiveUpdatePublisher`（`:163-170`，ETA / 汇合档位，`merging` 内部按单号过滤）、`blindStartConfirmedPublisher`（`:174-185`，信封无 `orderId`，只认汇合态）、`volunteerLostPublisher`（`:189-196`，无 `orderId`，判 `isTakenAwayWhenVolunteerLost`）、`$latestSeparationAlert.dropFirst()`（`:199-210`，只认本单 `ESCORT_DISTANCE_ALERT`，只改提示条与触觉）。

**测试现状**：`statusUpdatePublisher` 在测试里有 11 处引用，全在 `AppRealtimeCoordinatorTests.swift`（报告写的 0 处已过时）；页面一侧没有能注入实时依赖的接缝。`simulateIncomingEventForTesting` 有 153 处用法。

## Goals / Non-Goals

**Goals:**
- 「跟住一张单」只在一个 module 里实现：订单页不再直接订阅协调器的任何 publisher，不再自己排轮询与位置过期任务。
- 两个订单页里不再出现 `AnyCancellable`；一条数据流只用 async/await。
- 对方位置新鲜度只有一个判据。
- 「谁念状态句」由结构判定，不靠主队列先后。
- 新 module 能在单测里用 Mock 客户端 + `simulateIncomingEventForTesting` 直接验证，不起 WebSocket。

**Non-Goals:**
- 不改 `AppRealtimeCoordinator` 的路由、去重、对账、重试；不改 `WebSocketService`（仍是 Combine）。
- 不改 `AppState` 的暂缓退出订阅（`AppState.swift:362`）：它是 App 级策略，不是页面。
- 不改首页的派单、邀请、恢复等其余订阅（`VolunteerHomeViewModel` 仍有 Combine，记为后续）。
- 不接 `RUN_PROGRESS`（`websocket-protocol.md` 有，iOS 现在落 `.unknown`）。
- 不改任何状态流转、取消入口、求助入口、派单 respond、通话磨合的判定；不改文案；不改 15 秒、5 秒、10 秒（轨迹节流）、1/2/4 秒。
- 不改协调器发不发 `RealtimeOrderStatusUpdate` 的规则。新 module **不判状态**，只转交协调器已校验的更新。

## Decisions

### 1. 形状：一个 App 级 tracker + 每个页面一条 track

```swift
@MainActor
final class OrderLiveTracker {            // AppRealtimeCoordinator 强持有一个（`orderLiveTracker`），它弱引用回协调器；对每条 track 只持弱引用
    func open(role: WSRole,
              polling: OrderPollingPolicy,
              peerFreshness: TimeInterval = LiveEscortSessionCoordinator.peerFreshness,  // 现有 init 注入点改走这里
              currentStatus: @escaping @MainActor () -> RunOrderStatus?,                // 读页面手上 order 的状态，判停用
              isSessionExpiryDeferred: @escaping @MainActor () -> Bool,                 // 读 appState.isSessionExpiryDeferred，只拦轮询
              load: @escaping @MainActor (Int64) async -> Void) -> OrderLiveTrack
    /// 首页念状态句前调。见第 6 节。
    func pageAnnouncement(for update: RealtimeOrderStatusUpdate, role: WSRole) async -> PageAnnouncement
}

@MainActor
final class OrderLiveTrack {              // 页面 ViewModel 强持有；ViewModel 释放 ⇒ track 释放 ⇒ tracker 的弱引用变 nil
    let events: AsyncStream<OrderTrackingEvent>
    func follow(orderID: Int64)           // 现在 startPolling 里的跟踪部分：登记活跃订单、（重）开轮询并立即拉一次、开始收对方位置
    func pause()                          // 现在 stopPolling 里的跟踪部分：停轮询、停收对方位置、发 .peerLocationExpired
    func acknowledge(_ update: RealtimeOrderStatusUpdate, spoke: Bool)   // 页面处理完一条 .status 后必调，见第 6 节
    func end()
}

enum OrderTrackingEvent: Sendable {
    case status(RealtimeOrderStatusUpdate)        // 两端
    case peerLocation(FreshPeerLocation)          // 两端，已过新鲜度判据与 GCJ-02 边界
    case peerLocationExpired                      // 两端，只在没有更新样本时发
    case liveUpdate(RealtimeOrderLiveUpdate)      // 陪跑员
    case blindStartConfirmed                      // 陪跑员，信封无 orderId，页面自己判汇合态
    case volunteerLost                            // 陪跑员，信封无 orderId，页面自己判
    case separationAlert(RealtimeSeparationAlert) // 陪跑员，只发 open 之后到的、本单的 ESCORT_DISTANCE_ALERT
}

enum OrderPollingPolicy { case blindRunner, volunteer }
enum PageAnnouncement { case pageSpoke, homeShouldSpeak }
```

- 报告建议的 `跟踪(订单号) → AsyncSequence` 拆成 `open` + `follow`，因为现状里**订阅寿命与轮询寿命不同**（见 Context「订阅的寿命」）：状态推送在页面 `onDisappear` 之后仍要送到 ViewModel，对方位置不送。合成一个调用会改变「页面被盖住时谁念状态句」。
- **刷新不是事件，是 tracker 调页面给的 `load` 闭包。** 如果刷新作为事件放进流里、页面 `for await` 里 `await load`，状态更新就会排在一次慢请求后面，违反现有需求「REST 详情还在路上时，状态推送立即生效」。所以 tracker 自己调度刷新（轮询到点、协调器请求刷新、订阅时已挂着的刷新），流里的事件页面都同步处理。
- 闭包类型都标 `@MainActor`（记忆 `unannotated-async-closure-property-crashes-on-device`）；页面传闭包时用 `[weak self]`，避免 track ↔ 页面循环引用。
- **刷新记账留在页面的 `load` 里，不搬进 tracker。** `load` 的 `defer` 照旧调 `completeOrderRefresh` / `failOrderRefresh`（包括陪跑员 403 转走也算权威那条）。理由：`load` 还有十几个不经过 tracker 的调用方（Context 列了），记账一搬走，这些路径就清不掉挂着的刷新；而 403 那条「没有订单也算权威」也表达不进一个返回值。tracker 只决定「什么时候调 `load`」。
- **轮询判停读页面手上的状态**（`currentStatus` 闭包返回 `order?.status`，含推送改写过的状态），判停的时刻照现状（第 4 节）。页面 `apply` 里到终态就注销 / 停轮询的那一层兜底照旧保留。
- **`open` 的重复调用**：跑者页每次 `onAppear` 都走 `configure`。规定 `open` 只在 ViewModel 第一次 `configure` 时调一次，之后的 `configure` 复用已有 track（替代现在的 `cancellables.removeAll()` + 重订）。回放已存的最新对方样本挂在 `follow` 上（跑者每次 `follow` 回放，陪跑员不回放）。
- **`open` 到 `follow` 之间**：现状 `configure` 就开始收对方位置，两端的 `configure` 与 `startPolling` 都是在同一个 `onAppear` 里先后调用（`BlindOrderStatusView.swift:670-677`、`VolunteerInServiceView.swift:133-134`），中间没有一个主线程周期。所以改成 `follow` 才收没有可观察的差别；写进「有意的改变」备查。
- **`pause()` 与 `end()` 都不注销活跃订单。** `follow` 只用不带 `status:` 的 `registerActiveOrder` 重载。注销仍由页面在终态做。
- **页面的 `startPolling` / `stopPolling` 保留**，只把跟踪部分换成 `follow` / `pause`。换单时清页面状态（跑者 `+Loading.swift:29-50`：`statusLogs`、`trackStats`、`completionTask`、倒计时、`keepWaitingLimitReached` 等）、`stopPolling` 里的 `cancelRunCountdown()`（跑者 `:77`）与 `confirmationTask?.cancel()`（陪跑员 `VolunteerInServiceViewModel.swift:243-244`）都留在页面。
- **`pause()` 只停轮询和对方位置**；状态、`liveUpdate`、`blindStartConfirmed`、`volunteerLost`、`separationAlert` 在页面被盖住时照常送达（现状 7 个订阅全程不断）。
- 刷新驱动的 `load` 照旧**不看登录暂缓**；暂缓只拦轮询。

### 2. 协调器怎么喂 tracker：直接调用，不经 Combine

协调器在下面几处**已有的发布旁边**加一行对 tracker 的调用，原有发布不删（首页与 `AppState` 还在用）：`statusUpdateSubject.send`（`+Routing.swift:43`）、`peerLocationSubject.send`（`:207`）、`orderLiveUpdateSubject.send`（`:99`、`:101`）、`blindStartConfirmedSubject.send`（`+Notifications.swift:16`）、`volunteerLostSubject.send`（`AppRealtimeCoordinator.swift:90`）、`latestSeparationAlert = event`（`+Notifications.swift:205`）、`pendingOrderRefreshIDs.insert`（`+Routing.swift:110`、`+OrderTracking.swift:97`）。

- 这样 tracker 内部没有 `AnyCancellable`，事件按 `route` 的调用顺序进同一条流。现状是 7 个独立订阅，`volunteerLost` 与紧跟着的 `REMATCHING` 谁先到页面取决于两个订阅的投递顺序；合成一条流后顺序就是协调器处理的顺序（`volunteerLost` 先、状态后，与 `+Routing` 现有注释的假设一致）。
- 备选：tracker 自己订阅协调器的 publisher。否决：tracker 就会同时持有 `AnyCancellable` 和 `Task`，把要消掉的问题挪了个地方。

### 3. 对方位置的新鲜度只在一处判

新类型 `PeerLocationFreshness`（值类型，`threshold` 默认取 `LiveEscortSessionCoordinator.peerFreshness`）：

- `accept(sample, now:) -> FreshPeerLocation?`：判角色方向、单号、`age <= threshold`、`BackendCoordinateNormalizer.backend` 成功；返回坐标、采样时刻、精度、剩余有效期。
- `isFresh(capturedAt:, now:)`：给跑者 REST 兜底判「WebSocket 样本还新不新」，替掉 `+VolunteerLocation.swift:97` 的字面量 `15`。注意：样本超过阈值时过期任务已把 `latestVolunteerWebSocketDate` 清成 nil，所以「兜底与过期用同一阈值」在行为上测不出来（换成 30 秒结果也一样），只能靠第 2 批验收「字面量 `15` 为 0」这条静态检查守住。
- 过期任务由 `OrderLiveTrack` 持有：每条 track 至多一个；新样本替换旧任务；到期且没有更新样本才发 `.peerLocationExpired`；`pause()` / `end()` / 换单取消任务并发一次 `.peerLocationExpired`。
- 页面收到 `.peerLocationExpired` 执行它自己的 `clearPeerLocation()`（跑者会连 REST 兜底写入的坐标一起清，与现状相同）。
- `LiveEscortSessionCoordinator.swift:287` 与 `BlindRunnerHomeView.swift:365` 也改用 `isFresh`。
- 回放：`follow` 时按角色决定是否回放协调器已存的最新样本——跑者回放，陪跑员不回放（照现状）。
- 阈值由 `open(peerFreshness:)` 注入，替代现在两个 ViewModel `init(peerFreshness:)` 的注入点（测试里 3 处用法随之改）。

### 4. 轮询策略两种，逐行照搬现状

| | 第一次拉之前 | 每一轮的顺序 | 停 |
|---|---|---|---|
| `.blindRunner` | 暂缓中不拉 | 判停 → 睡 5 秒 → 拉 | 暂缓中；或 `currentStatus()` 不为 nil 且 `!shouldPoll` |
| `.volunteer` | 暂缓中不拉 | 睡 5 秒 → 拉 → 判停 | 拉完后 `currentStatus()` 是终态（`isTerminal`）；或暂缓中 |

间隔取 `AppConstants.Timing.orderPollingInterval`（可注入，单测用小值）。暂缓判断由页面在 `open` 时传入（读 `appState.isSessionExpiryDeferred`，与原有循环读的是同一个值）。

> 第 1 批实现时改（#886）：原设计让 `AppState` 持有 tracker 并注入暂缓判断，但 `AppState.swift` 的文件长度与 `init` 长度都在 SwiftLint 棘轮的上限上（404 行 / 71 行），加 4 行就红。改成协调器持有、页面传入，`AppState` 一行不改，行为不变。

### 5. 刷新调度

- 协调器请求刷新某单 → 正在 `follow` 这一单的 track 调一次 `load`。`open` / `follow` 时该单已在 `pendingOrderRefreshIDs` 里，也补调一次（现状 `$pendingOrderRefreshIDs` 订阅时会立即收到当前值）。
- 推送触发的刷新与轮询**照旧可以并行**，过时的响应仍由 `OrderStatusReconciler` 的 request token 挡掉。备选「同一时间只跑一个刷新」否决：会让推送触发的刷新排在一次慢轮询后面，是行为变化。
- 有意不保留的一点：现状 `$pendingOrderRefreshIDs` 在集合里**任何一单**变化时都会对本单再拉一次（只要本单还在集合里）。tracker 只在本单被请求时拉。这只少掉重复请求，不少掉任何一次被请求的刷新。

### 6. 状态句由谁念：订单页先处理、再告诉首页（负责人已确认，见「已确认」）

只看「订单页开着没有」不够：页面有几种情况收到推送却不念（`order` 还没拉回来时守卫直接丢弃，`VolunteerInServiceViewModel.swift:145-147` / 跑者 `+Realtime.swift:21-23`；陪跑员 `apply` 里取消类分支不念通用句，`+OrderUpdates.swift:27`）。首页照这个判据静默，盲人会一句都听不到。所以判据落在「页面这一次念了没有」：

- 页面处理每条 `.status` 后**必须**调 `track.acknowledge(update, spoke:)`：念了状态句（或用自己的整句覆盖了它）就 `spoke: true`，被守卫丢弃或刻意不念就 `spoke: false`。
- 首页念某单的状态句之前 `await tracker.pageAnnouncement(for:role:)`：
  - 没有页面在跟这一单（没有活着的 track 在 `follow` 它）→ 立即返回 `.homeShouldSpeak`；
  - 有 → 等这个页面对**这一条**更新的 `acknowledge`，`spoke: true` 返回 `.pageSpoke`（首页不念），`spoke: false` 返回 `.homeShouldSpeak`；
  - 等待上限 1 秒（具名常量），超时按 `.homeShouldSpeak`。宁可偶尔两句，不能零播报。
- 首页的「当前订单」更新不等这个结果，照常同步做；只有念不念等。
- track 的寿命跟页面 ViewModel：ViewModel 是 `@StateObject` 强持有 track，tracker 只弱引用 track。ViewModel 释放后弱引用自然为 nil，不需要在 `deinit` 里调 isolated 的 `end()`。
- **完成（`COMPLETED`）照现状两边都念**：跑者页的完成句走独立任务、刻意不过去重通道（`+TrackStats.swift:145-147`），现状首页那句通用句与触觉同时存在。页面对完成态 `acknowledge(spoke: false)`，首页照念。要不要改另议。
- 陪跑员端：取消（跑者取消 / 自己取消）页面念整句 → `spoke: true` → 首页不念，等价于现状 #462 的意图，删掉 `DispatchQueue.main.async` 那一拍。`+OrderUpdates.swift:68-70` 的 `markStatusAnnounced(.cancelled)` 第 3 批保留作纵深防御，注释改成指向本节。
- 跑者端：现状是两个 Combine 订阅谁先投递谁念（首页 `blindRunnerAnnouncement()`，订单页 `statusChangeAnnouncement(from:to:)`），**顺序没有任何东西保证，也没有用例钉住**。两句不同，只有订单页那句会说：通话磨合没成退回 `PENDING_MATCH` / `REMATCHING` 的「本次见面安排未生效」或本轮结束，以及双方都说合适转 `PENDING_ACCEPT` / `SCHEDULED_CONFIRMED` 的整句约定（`BlindIntroCallOutcomeCopy.agreed`，`+StatusTransitions.swift:136-147`）。本设计让订单页先念。

### 7. 订单页里留什么

页面 ViewModel 只剩：持有一条 `OrderLiveTrack` 和一个消费它的 `Task`；一个同步的 `handle(_ event:)`，把每种事件映射到现有的处理（`apply`、`isLoading`、`errorMessage`、`latestBlindSample`、`awaitingBlindConfirmation`、`leaveLostOrder`、`separationAlertAt` + 触觉……原样搬进来，判据不改）；`load` 本身。与跟踪无关的 `Task`（陪跑员 `confirmationTask`、`dispatchSummaryTask`；跑者 `runCountdownTask`、`completionTask`）不动。

## 分批与验收

每批一个 PR，只过编译门禁（`build-for-testing`）与规格校验；新用例写进 PR，标「已写，未执行」。

**第 1 批：tracker 与新鲜度判据（不动任何页面）**
- 新增 `OrderLiveTracker.swift`、`PeerLocationFreshness.swift`；协调器持有 tracker；协调器加第 2 节列的直接调用。
- 单测（Mock 客户端 + `simulateIncomingEventForTesting`）：合法状态事件进流；`toStatus` 为未知值时流里没有 `.status`、`load` 被调一次；重复 `messageId` 不进流；别的单的事件不进流；14 秒前的样本进流、16 秒前的不进；样本到期发 `.peerLocationExpired`，被新样本替换时旧的不发；两种轮询策略的停止顺序各一条（用例要能区分「先判后拉」与「先拉后判」）；首页问 `pageAnnouncement`：无页面立即 `.homeShouldSpeak`、页面 `spoke: true` 返回 `.pageSpoke`、页面 `spoke: false` 与超时都返回 `.homeShouldSpeak`；页面 ViewModel 释放后视为无页面；`open` 时已挂着的刷新会补拉一次；`end()` 后不再调 `load`。
- 验收：编译通过；页面行为零变化（diff 不含 `blindRun/BlindRunner/`、`blindRun/Volunteer/`）。

**第 2 批：跑者订单页迁过去**
- `BlindOrderStatusViewModel+Realtime.swift` 改为 `open` + 消费 `Task`；`+Loading.swift` 的轮询循环删掉，`startPolling` / `stopPolling` 改调 `follow` / `pause`；`+VolunteerLocation.swift` 的新鲜度与过期改用第 1 批；`BlindOrderStatusView.swift:210` 的 `cancellables` 删掉。
- 跑者首页 `applyRealtimeStatus` 加第 6 节的判断（只影响念不念，`activeOrder` 照常更新）。
- 验收：编译通过；`BlindOrderStatusViewModel*` 与 `BlindOrderStatusView.swift`（类定义在这里，`:1`、`:210`）里 `AnyCancellable` / `import Combine` 为 0；`peerFreshness` 字面量 `15` 为 0；补用例：订单页开着时只念订单页那句（通话磨合退回 `PENDING_MATCH`、退回 `REMATCHING`、`agreed` 各一条）；订单页的 `order` 还是 nil 时首页念；订单页没开时首页念；完成态两边都念。

**第 3 批：陪跑员订单页迁过去**
- `VolunteerInServiceViewModel.swift` 的 7 个 `AnyCancellable` 与 `pollingTask`、`peerExpiryTask` 换成一条 track；`+Nudges.swift`、`+OrderUpdates.swift` 的新鲜度与过期改用第 1 批。
- 陪跑员首页 `VolunteerHomeViewModel+Realtime.swift:38-46` 改为第 6 节的判断，删掉 `DispatchQueue.main.async`。
- 验收：编译通过；`VolunteerInServiceViewModel*` 里 `AnyCancellable` 为 0；补用例：跑者取消时只念「不算你的取消」那句；自己取消（`REMATCHING`）只念一句；失联事件后紧跟 `REMATCHING` 不念「订单已取消」；走散告警只改提示条、不改订单状态；`BLIND_START_CONFIRMED` 只在汇合态清「等待对方确认」。

**第 4 批：守卫与收尾**
- `scripts/hooks/guard.mjs` 加一条：`blindRun/` 下除 `Core/` 外出现 `statusUpdatePublisher`、`peerLocationPublisher`、`$pendingOrderRefreshIDs`、`orderLiveUpdatePublisher`、`blindStartConfirmedPublisher`、`volunteerLostPublisher` 就拦（首页还在用的那几个按当时实际列白名单，白名单只减不增）。
- `docs/review/architecture-20261108.md` 结论表候选 5 填实际 PR 号。
- 验收：守卫在一个故意违规的临时文件上报红、删掉后报绿（PR 里贴两次输出）。

## 必须原样保留的行为（每批 PR 逐条对照）

1. 只有协调器校验过的状态更新才改本地状态；未知状态值、`fromStatus` 对不上、重复 `messageId` 都只触发刷新（或丢弃），页面不空白、不崩。
2. 状态推送立即生效，不等 REST 详情；过时的 REST 响应不让状态倒退。
3. 通话磨合没成退回 `PENDING_MATCH`（不是 `REMATCHING`）的处理与播报不变。
4. 盲人在 `DRIVER_EN_ROUTE` / `IN_PROGRESS` 没有取消入口；`DRIVER_ARRIVED` 的取消门槛只认 `earliestBlindCancelAt`。本变更不碰这些判定的代码。
5. `confirm-departure` 与 `en-route` 仍是两个动作；本变更不碰流转端点。
6. 求助入口仍只读 `BlindHomeSOSMode.resolve` / `VolunteerOrderSOSMode.resolve`；本变更不碰求助代码。
7. `ESCORT_DISTANCE_ALERT` 只改提示条与触觉，不改状态、不开求助界面。
8. 对方位置 15 秒过期；过期只清比它旧的标记；离页、换单、终态清标记。
9. 两端轮询间隔 5 秒、停止条件按第 4 节表格；登录暂缓中两端都不轮询。
10. 刷新失败按 1/2/4 秒重试，之后放弃。
11. 失联事件、`BLIND_START_CONFIRMED` 没有 `orderId`，判据仍是页面手上订单的状态。
12. 陪跑员端「跑者取消」「自己取消」「失联转走」三种情况各只念一句。
13. 坐标只过一次 GCJ-02 边界（`BackendCoordinateNormalizer`），不记日志。
14. `load` 的刷新记账（含陪跑员 403 转走算权威）留在 `load` 里，所有调用方不变。
15. `stopPolling` 不注销活跃订单；注销只在终态由页面做。
16. 页面被盖住时，除对方位置外的所有事件照常送达。
17. 刷新驱动的拉取不看登录暂缓。
18. 完成态的播报两边都念（跑者页完成句 + 首页通用句与触觉）。

## 有意的改变（每条要负责人知情）

1. 首页念不念状态句由「订单页这一次念了没有」决定（第 6 节）。陪跑员端等价于现状意图；跑者端从「看投递顺序」变成「订单页优先」。
2. 订单页开始收对方位置的时刻从 `configure` 挪到 `follow`（同一个 `onAppear` 里先后调用，无可观察差别）。
3. 刷新只在本单被请求时拉，不再因集合里别的单变化而重复拉（第 5 节）。
4. 对方位置的单号比对从「页面已拉回的 `order?.orderId`」变成「track 正在跟的单号」：陪跑员页原来在详情拉回之前一律丢样本（`VolunteerInServiceViewModel+Nudges.swift:98-100`），现在 `follow` 之后就收（第 1 批复核 B5）。只会让 15 秒内的样本更早显示。

## 第 2、3 批接入时要确认的（第 1 批复核记下）

- `end()` 会取消在途的刷新任务，页面 `load` 里的请求随之取消。接入时确认 `load` 把取消当什么：若在 `defer` 里走 `failOrderRefresh`，会给协调器多排一次 1/2/4 秒重试（复核 B6）。页面释放时不调 `end()`（靠弱引用），这条只影响显式 `end()`。

## 风险 / 取舍

- [订单页从 Combine 换成 `AsyncStream`，投递时机变了] → 状态句不再依赖投递顺序（第 6 节）；其余事件的处理都是幂等赋值，先后只影响同一主线程周期内的中间值。
- [tracker 成了一个新的单点] → 它不判状态、不调流转端点，只转交与调度；协调器的校验一行不改。第 1 批的单测直接覆盖它。
- [首页等页面回话，可能拖慢或吞掉播报] → 页面同步处理事件后立即 `acknowledge`；等待上限 1 秒，超时首页照念；页面释放即视为无页面。第 1 批单测覆盖这四种情况。
- [第 2、3 批之间两端写法不一致] → 两批间隔短；第 2 批合并后、第 3 批合并前，陪跑员端仍是旧写法、行为不变。
- [后端文档内部不一致] → `websocket-protocol.md` §六说 `GET /api/blind/volunteer-location`「仅在 `DRIVER_EN_ROUTE` 或 `DRIVER_ARRIVED` 返回数据」，`api_spec.yaml:874-888` 的回归门却是 `volunteerLocationFallback_worksDuringInProgress`。iOS 现状按 api_spec（`fetchesVolunteerLocation` 含 `IN_PROGRESS`），本变更照旧。已开后端 issue（Jayden23018/blind-run-backend#942，低）请他们统一文档。
- [真机没有执行任何新用例] → 11-05 起只验编译。每批 PR 写清「已写，未执行」；负责人真机跑完再归档本变更。

## 已确认（负责人 2026-11-08 原话：「批准，按推荐答三问」）

1. **跑者端状态句以订单页为准？** 答：是。理由：通话磨合退回与成单时只有订单页那句带具体内容；现状谁念取决于没有保证的投递顺序。选否则第 2 批改成「首页念、订单页不念」，同样按结构判。
2. **刷新是否改成「同一时间只跑一个」？** 答：否（第 5 节），保持并行。
3. **陪跑员订单页进页时要不要也回放最新的对方位置？** 答：不改（照现状不回放）。
