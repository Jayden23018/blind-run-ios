## 0. 批准

- [ ] 0.1 负责人批准本变更，并回答 design.md「待确认」三问（跑者端状态句以谁为准、刷新是否单飞、陪跑员是否回放）

## 1. 第 1 批：tracker 与新鲜度判据（不动页面）

- [ ] 1.1 新建 `blindRun/Core/PeerLocationFreshness.swift`：`accept(sample, now:)`、`isFresh(capturedAt:now:)`，阈值默认 `LiveEscortSessionCoordinator.peerFreshness`
- [ ] 1.2 新建 `blindRun/Core/OrderLiveTracker.swift`：`OrderLiveTracker`、`OrderLiveTrack`、`OrderTrackingEvent`、`OrderPollingPolicy`、`PageAnnouncement`；闭包一律标 `@MainActor`；tracker 对 track 只持弱引用；内部不持有 `AnyCancellable`
- [ ] 1.3 `AppState` 持有一个 tracker，注入「是否暂缓中」与轮询间隔
- [ ] 1.4 协调器在 design.md 第 2 节列的发布点旁各加一行直接调用 tracker，原发布不删
- [ ] 1.5 单测（design.md 第 1 批清单）；轮询停止顺序的两条用例要能区分「先判后拉」与「先拉后判」
- [ ] 1.6 编译门禁；确认 diff 不含 `blindRun/BlindRunner/`、`blindRun/Volunteer/`；PR 写「用例已写，未执行」

## 2. 第 2 批：跑者订单页

- [ ] 2.1 `BlindOrderStatusViewModel+Realtime.swift` 改为 `open` + 一个消费 `Task`，`handle(_:)` 同步处理每种事件，判据照搬
- [ ] 2.2 `+Loading.swift` 删轮询循环，`startPolling` / `stopPolling` 里的跟踪部分改调 `follow` / `pause`，换单清状态、`cancelRunCountdown()` 留在页面；`loadOrder` 的刷新记账不动；`open` 只在第一次 `configure` 调
- [ ] 2.3 `+VolunteerLocation.swift` 新鲜度与过期改用第 1 批；`:97` 的字面量 `15` 改用 `isFresh`；`BlindOrderStatusView.swift` 删 `cancellables`
- [ ] 2.4 跑者订单页每条 `.status` 处理后 `acknowledge`（完成态 `spoke: false`）；跑者首页 `applyRealtimeStatus` 念之前 `await pageAnnouncement`（按 0.1 的答复），`activeOrder` 照常同步更新
- [ ] 2.5 补用例（design.md 第 2 批清单）；编译门禁；对照 design.md「必须原样保留的行为」逐条写进 PR

## 3. 第 3 批：陪跑员订单页

- [ ] 3.1 `VolunteerInServiceViewModel.swift` 的 7 个 `AnyCancellable` 与 `pollingTask`、`peerExpiryTask` 换成一条 track
- [ ] 3.2 `+Nudges.swift`、`+OrderUpdates.swift` 新鲜度与过期改用第 1 批；`load` 的刷新记账（含 403 转走）不动；`stopPolling` 里 `confirmationTask?.cancel()` 留在页面
- [ ] 3.3 陪跑员订单页 `acknowledge`；`VolunteerHomeViewModel+Realtime.swift:38-46` 改为 `await pageAnnouncement`，删 `DispatchQueue.main.async`；`+OrderUpdates.swift:68-70` 的 `markStatusAnnounced` 保留、改注释
- [ ] 3.4 补用例（design.md 第 3 批清单）；编译门禁；对照「必须原样保留的行为」逐条写进 PR

## 4. 第 4 批：守卫与收尾

- [ ] 4.1 `scripts/hooks/guard.mjs` 加守卫：`blindRun/` 下 `Core/` 以外直接用订单跟踪相关 publisher 就拦（首页仍在用的列白名单）；在故意违规的临时文件上验红、删掉后验绿
- [ ] 4.2 `docs/review/architecture-20261108.md` 结论表候选 5 填实际 PR 号

## 5. 收尾

- [ ] 5.1 负责人真机跑第 1–3 批新增与改动的用例，执行数不为 0
- [ ] 5.2 全部勾完后归档本变更
