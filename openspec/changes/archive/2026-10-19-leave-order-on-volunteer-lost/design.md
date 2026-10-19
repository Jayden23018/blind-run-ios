## Context

后端 `OrderLifecycleService.handleVolunteerLost` 依次发三条：给跑者与原陪跑员各一条 `ORDER_VOLUNTEER_LOST`（模板通知，`sendNotification(..., null)`，**信封与 `notification_logs` 都没有 `orderId`**），再发 `ORDER_STATUS_CHANGED`（→`REMATCHING`，带 `orderId`）给双方。之后原陪跑员调 `GET /api/orders/{id}` 回 403 `ORDER_PERMISSION_DENIED`。

iOS 现状：
- 横幅在 `ContentView` 用默认档 `.counterpartAction` 念 `speechText`。
- 订单页 `VolunteerInServiceViewModel.apply` 遇到 `REMATCHING` 一律走「取消那一句」：同档念「订单已取消，这一单不在你名下了。」，切断前面的横幅；随后 `order = nil`、停轮询，但只有「自己按取消」那条路会 `dismiss()`，推送来的 `REMATCHING` 让页面停在兜底页的转圈。
- 首页 `VolunteerHomeViewModel` 也订阅状态推送，清 `activeOrder` 并念同一句（与订单页共用去重键）。

## Goals / Non-Goals

**Goals:** 失联事件到达时两处都静默放下这一单，只留横幅那一句；推送来的 `REMATCHING` 不再把页面卡住。

**Non-Goals:** 不改 `ORDER_DEPARTURE_STALLED` / `REMATCHING_MID_RUN` / `SCHEDULED_DEPARTURE_GATE_MISSED` 的处理与文案；不处理详情接口 403（重连补读会带回这条事件，见风险）；跑者端不变。

## Decisions

1. **协调器发一条不带订单号的通道 `volunteerLostPublisher`**，与 `blindStartConfirmedPublisher` 同形。实时 `routeNotification` 与补读 `ingestCatchUp` 都发；只在陪跑员角色（或未绑定角色的测试）发。通知本身照旧按安全提醒入队，不改。
   - 备选：把它映射成一次 `REMATCHING` 状态更新。否决：没有 `orderId`，且会走到念「订单已取消」那条路。
2. **由手上订单的状态判归属**：只有 `DRIVER_EN_ROUTE` / `DRIVER_ARRIVED` 才放下（后端看门狗只在这两态动手）。判据写成 `RunOrderStatus` 上的穷举 switch，后端加状态时编译器会逼一次决策。`IN_PROGRESS` 不放下：跑步页是安全相关页面，宁可等状态推送。
3. **静默放下 = 注销活跃订单**（`unregisterActiveOrder`）。随后那条 `ORDER_STATUS_CHANGED` 在协调器里就不再发布给两处订阅者，两边都不会念状态句；不用 `markStatusAnnounced(.rematching)`，因为那个去重键会留到下一单，吞掉陪跑员下一次自己取消时那一句。
4. **订单页用独立标志 `didLoseOrder` 驱动离开**，不复用 `didCancelOrder`：后者属于「自己按了取消」那条路，那条路在取消面板的回调里自己 `dismiss()`，两处同时 dismiss 会抢。推送来的 `REMATCHING` 是否「自己发起」看 `VolunteerCancelAnnouncement` 是否 `begin()` 过（新增 `requested`）。
5. **离开前收起面板再 dismiss**：有面板开着时等收起动画再 dismiss，避免在面板消失的同一拍弹出导航。
6. 离开后在路上的流转请求（`submitTransition`）回来时不再念结果也不再起确认任务；新点按因 `order == nil` 自然不会发请求。

## Risks / Trade-offs

- [补读来的旧事件撞上新的出发中订单] → 补读游标只取上次见过之后的通知，这种情形需要他错过这条推送后又走到另一单的出发中、期间一条通知都没收到。真发生时首页下次刷新会把新单带回来，可再点进去。
- [失联事件与状态推送都没到] → 页面仍按旧行为停在原状态，轮询拿到 403 被吞掉。后续可把 403 `ORDER_PERMISSION_DENIED` 也当作「已不是参与者」，本次不做。
- [推送来的 `REMATCHING`（非失联、非自己取消，如跨天闸门到点）] → 仍念原来那一句「订单已取消，这一单不在你名下了。」，只是现在会离开页面。
