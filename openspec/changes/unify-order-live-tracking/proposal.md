## Why

两端订单页都要「跟住一张单」：收状态推送、收到「需要刷新」就重拉详情、收对方位置并在 15 秒后让它过期、WebSocket 断了靠 5 秒轮询兜底。现在这件事没有自己的 module，每个页面各拼一遍：

- 一次状态变化经过 6 处：`WebSocketService.eventPublisher` → `AppRealtimeCoordinator.attach` 的 `.sink`（`blindRun/Core/AppRealtimeCoordinator.swift:201`）→ `route`（`+Routing.swift:6`）→ `statusUpdatePublisher` → 页面 ViewModel → `apply()`。
- `statusUpdatePublisher` 有 5 个订阅方：跑者订单页 `BlindOrderStatusViewModel+Realtime.swift:18`、陪跑员订单页 `VolunteerInServiceViewModel.swift:142`、陪跑员首页 `VolunteerHomeViewModel+Realtime.swift:19`、跑者首页 `BlindRunnerHomeView.swift:143`、`AppState.swift:362`（暂缓退出）。两个订单页的订阅几乎逐行相同（跑者 `+Realtime.swift:10-31`，陪跑员 `VolunteerInServiceViewModel.swift:133-154`）。
- 对方位置过期写了两份（跑者 `BlindOrderStatusViewModel+VolunteerLocation.swift:5-23`、`:52-81`；陪跑员 `VolunteerInServiceViewModel+Nudges.swift:98-114`、`+OrderUpdates.swift:75-95`）。15 秒阈值 `LiveEscortSessionCoordinator.peerFreshness`（`LiveEscortSessionCoordinator.swift:55`）被各处分别引用，`BlindOrderStatusViewModel+VolunteerLocation.swift:97` 还另写了一个字面量 `15`。
- 两个轮询循环各写一份，停止条件不同（跑者 `+Loading.swift:55-69`，陪跑员 `VolunteerInServiceViewModel.swift:220-237`）。
- `VolunteerInServiceViewModel` 同时持有 7 个 `AnyCancellable` 与 4 个 `Task`，跑者订单页持有 `cancellables` 与 4 个 `Task`，违反 `CLAUDE.md`「并发模型只用一种」。`.sink { Task { await load } }`（`VolunteerInServiceViewModel.swift:136-138`、跑者 `+Realtime.swift:12-14`）就是两种模型串在一条数据流上。
- 陪跑员首页与订单页「谁先念状态句」靠两个 Combine 订阅都排在主队列上、首页再 `DispatchQueue.main.async` 推迟一拍来保证（`VolunteerHomeViewModel+Realtime.swift:38-46`，#462 / #477）。订单页一换成 async/await，这个先后就不再成立。

前端全仓审查第 3 轮（#857 候选 5，`docs/review/architecture-20261108.md` §5）把它列为要合成一个深 module 的浅 module。它碰订单状态机（AGENTS §5），按 §10 第 5 步属大档。

## What Changes

- 新增一个 module「订单跟踪」：页面调一次 `track(订单号, 角色)`，拿到一个 `AsyncSequence`，里面依次给出：状态更新、需要刷新（推送触发或轮询到点）、对方位置（已过新鲜度判据）、对方位置已过期，以及陪跑员端的 ETA / 汇合档位、跑者已确认开跑、单被转走、走散告警。页面只消费事件、自己决定怎么渲染和念。
- 对方位置的新鲜度只在这个 module 里判一次：一个阈值（15 秒，不改值）、一个过期定时，两端共用；REST 兜底判「WebSocket 样本还新不新」也用同一个判据，去掉字面量 `15`。
- 轮询兜底并进这个 module。两端的停止条件按现状各自保留（跑者：状态不再需要轮询就停；陪跑员：拉到终态就停；两端：登录暂缓中都停）。
- 状态句「念一次、用谁的句子」改成按结构判：本单的订单页开着时，首页不念这一单的状态句，由订单页念；订单页没开时首页照常念。替掉「主队列先后 + 推迟一拍」。
- 分 4 批落地（详见 design.md）。每批一个 PR，只过编译门禁，新用例「已写，未执行」。
- 不变：`AppRealtimeCoordinator` 的路由、去重、状态对账（`OrderStatusReconciler`）、刷新重试 1/2/4 秒；推送内容的取舍；状态机、取消入口、求助入口、派单 respond、通话磨合页的任何判定；所有文案；15 秒与 5 秒两个值。`WebSocketService` 仍是 Combine，协调器对它的订阅不改。

## Capabilities

### New Capabilities

（无）

### Modified Capabilities

- `global-realtime-notification-handling`: 新增两条需求：「两端订单页用同一种方式跟住一张单」（状态更新、未知状态降级、刷新、轮询兜底与停止条件、离页停止）；「状态变化句只念一次，订单页开着时由订单页念」。
- `live-escort-location-and-track-summary`: 修改「Associated participants receive fresh peer positions」：新鲜度判据与过期改为两端共用一处，REST 兜底的 WebSocket 新鲜度判断用同一判据。

## Impact

- 代码（批准后，按批）：新文件 `blindRun/Core/OrderLiveTracker.swift`、`blindRun/Core/PeerLocationFreshness.swift`；`blindRun/Core/AppRealtimeCoordinator+Routing.swift`（把已有的发布同时交给 tracker，只加不改）；跑者 `BlindOrderStatusView.swift`（ViewModel 属性）、`BlindOrderStatusViewModel+Realtime.swift`、`+Loading.swift`、`+VolunteerLocation.swift`；陪跑员 `VolunteerInServiceViewModel.swift`、`+Nudges.swift`、`+OrderUpdates.swift`；首页 `VolunteerHomeViewModel+Realtime.swift`、`BlindRunnerHomeView.swift`；守卫 `scripts/hooks/guard.mjs`。
- 红线：碰订单状态机的消费端（AGENTS §5）与走散告警的投递（§6「只是提示」）。本变更不新增、不删除任何状态流转、取消入口或求助入口；新 module 不判状态（只转交 `AppRealtimeCoordinator` 已校验过的更新），不调用任何流转或求助端点。
- 契约：不改。依据 `docs/websocket-protocol.md`（`ORDER_STATUS_CHANGED`、`VOLUNTEER_LOCATION_UPDATE`、`BLIND_LOCATION_UPDATE`、`ORDER_ETA_UPDATED`、`MEET_DISTANCE_BUCKET`）与 `api_spec.yaml` 的 `GET /api/blind/volunteer-location`（后端 origin/main 998c6bc8）。后端文档内部有一处不一致（见 design.md「风险」），不影响本变更。
- 依赖：无在途 PR 改这些文件（#880 改跑后记录页）。#862（陪跑员首页摘要刷新）若先开工，与第 4 批的 `VolunteerHomeViewModel` 有重叠，届时先合它。
- 测试：新 module 的单测可以不起 WebSocket、不连服务器，直接喂协调器事件（`simulateIncomingEventForTesting` 已有 153 处用法）。CI 只能编译，单测与 UI 测试按 11-05 起的规矩写「已写，未执行」。
