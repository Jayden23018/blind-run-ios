> # ▶ 状态：已重启（RESTARTED — 2026-07-31）｜交付范围于 2026-08-01 恢复为双角色
>
> **重启日期**：2026-07-31 ｜ 取代同日更早的「本版不交付」决策（提交 `443e741`），该决策**已作废**。
>
> **重启的依据：不再空等后端答复，改为直接读后端实现定契约。**
> `design.md` 的 5 个 `需要人工确认` 至今无书面答复，但其中 3 个已由前端读后端源码得到事实性答案，
> 另外 2 个已用「守卫默认严格 + 一个常量可翻转」的方式绕开。逐条见下。
>
> **交付范围：双角色，与本文 What Changes 一致。** 重启当天（2026-07-31）曾收窄为「仅盲人侧」，
> **该收窄已于次日作废**，本块保留原因是它解释了志愿者侧为何一度关闭：
>
> - ✅ **盲人侧 `IN_PROGRESS` SOS 交付**——后端链路核实正确。
> - ✅ **志愿者侧 `IN_PROGRESS` 入口同样交付**（`4793805`，2026-08-01）。
>   ~~继续隐藏——不是前端没做，是后端会送错人~~：原理由是 `EmergencyService.java` 把事件挂在
>   **触发者** `event.userId` 上，于是志愿者触发时告警回推给触发者自己、30 秒后升级查的是
>   **志愿者本人**的紧急联系人（志愿者没有强制录入）→ 走 `EMERGENCY_NO_CONTACT`，
>   盲人的家属恰恰不会被联系。**后端 commit `a5ba523`（SOS-1，2026-07-31）已把 `event.userId`
>   改为取订单的盲人方**，并用 `TriggerType.VOLUNTEER_BUTTON` 区分来源，该理由自那天起不成立。
>   代码事实：`RunOrderStatus.canVolunteerTriggerEmergency == (self == .inProgress)`
>   （`blindRun/Core/Models/OrderModels.swift:140-142`）。
> - ⛔ **志愿者没有、也不会有「误触」撤销入口**——后端对志愿者的 `action=FALSE_ALARM` 恒回 403
>   `EMERGENCY_VOLUNTEER_CANNOT_DISMISS`：一对一陪跑里志愿者可能就是威胁来源，撤销权只在受助者
>   本人（`PUT /api/emergency/{id}/cancel`）和客服手里。这一条是产品红线，不随后端能力变化。
>
> **三条已由代码核实的事实（据此定文案，不再等答复）**
>
> 1. **`EMERGENCY_CONTACT_NOTIFIED` 发出时，短信一次都还没尝试发。**
>    `EmergencyService.java:370-373` 的 WS 推送是**事务内同步**的，注释自陈「保证盲人即时收到"已通知家属"反馈」；
>    真正发短信的 `EmergencyContactNotifier.onNotifyContacts` 是
>    `@TransactionalEventListener(AFTER_COMMIT)` + `@Async`（`:60-62`），**严格在其之后**。
>    → App **永久禁用**「联系人已收到短信」「已通知家属」这类完成时文案，只用进行时。
> 2. **短信失败时盲人收不到任何更正。** `EmergencyContactNotifier.java:126-135` 只把
>    `EMERGENCY_SMS_FAILED` 广播给客服。→ 文案按最坏情况写，全程不承诺送达。
> 3. **`EMERGENCY_CONTACT_NOTIFIED` 不是顶层 WS 类型，也不带 `eventId`。**
>    `docs/websocket-protocol.md:222-234` 写的是 `{"type":"EMERGENCY_CONTACT_NOTIFIED","eventId":456,...}`，
>    但实现走 `NotificationService.sendNotification` → `buildEnvelope("APP_NOTIFICATION")`（`:93-99`），
>    实际是 `{"type":"APP_NOTIFICATION","eventType":"EMERGENCY_CONTACT_NOTIFIED","body":...}`，**无 eventId / orderId**。
>    → `design.md` 决策 5 的**原文**「按 eventId 匹配后才展示短信文案」在当前后端**不可能成立**；
>    该规则退化为其守卫含义：**该文案永不展示**（决策 5 已按此改写，见 `design.md:53`）。
>    契约文档与实现不一致一事已投递后端。
>
> **两条产品决策用可翻转常量绕开，不阻塞交付**
>
> 4. **严格 GPS 门槛**（`design.md:45`，决策 3）：默认**严格阻断**，
>    `EmergencyCoordinator.allowsSubmissionWithoutLocation = false`。后端 `EmergencyTriggerRequest`
>    的 `gpsLat/gpsLng` 本就可空（降级路径存在），产品/安全批准后改这一个常量即可。
> 5. **断线重启后的事件恢复**（`design.md:107`）：后端**没有**任何查询端点或重放机制。
>    → 前端**不持久化**任何事件元数据，进程重启即清空。
>    这样「不得把未经后端确认的状态当权威呈现」自动成立，零代码。
>
> **仍然不变的红线**：二次确认文案必须与 `AGENTS.md` 第 10 节原文逐字一致；
> 禁止任何 Mock/兜底坐标进入云端请求；SOS 不改变 `RunOrderStatus`。

## Why

The backend accepts emergency triggers from blind-runner and volunteer tokens and owns emergency-contact SMS escalation, but the iOS release at the time of this proposal intentionally hid both emergency entries. The approved scope is now narrower and safer than the earlier independent-SOS proposal: only the two participants of an `IN_PROGRESS` run may initiate an order-associated SOS, and the app must never claim SMS success at all (see fact 1–2 in the status block above).

The existing change ID is retained for continuity, but its former independent blind-runner capability is replaced by a dual-role in-run safety flow.

## What Changes

- **BREAKING** Remove the proposed always-reachable/no-order blind SOS and enable an SOS entry only for the associated blind runner and volunteer while canonical order status is `IN_PROGRESS`.
- Require the exact project-mandated second-confirmation text before every trigger.
- Submit the owned `orderId` and a fresh real GCJ-02 GPS coordinate from the live escort session to `POST /api/emergency/trigger`.
- Treat trigger success as a separate emergency event keyed by backend `eventId`; never synthesize or mutate `RunOrderStatus`.
- Never present “联系人已收到短信” or any other delivery claim in any state — the backend emits its contact-notified event before the SMS is attempted and never corrects a failure back to the blind runner (fact 1–2 above), so the app substitutes its own progressive-tense copy for the backend body and shows only submitted/processing state.
- Route the same pending, failed, contact-notified, and resolved safety state across both role experiences through the app-lifetime realtime coordinator.
- Keep SMS delivery, reverse geocoding, emergency-contact selection, CS escalation, schedulers, and rescue operations backend-owned.

## Capabilities

### New Capabilities

- `in-run-dual-role-sos`: Defines dual-role `IN_PROGRESS` eligibility, exact confirmation, required order/current-GPS association, event state, never-claim-delivery SMS copy, accessibility, and unchanged order lifecycle.

### Modified Capabilities

- `formal-dispatch-service-flow`: Replaces the current hidden emergency requirement with the approved `IN_PROGRESS`-only dual-role entry.
- `backend-api-contract`: Defines both-role trigger authorization, structured trigger result, GCJ-02 fields, event recovery, and typed contact-notified/resolved WebSocket messages for both participants.
- `global-realtime-notification-handling`: Routes emergency events by event/order/role independently of screen lifetime.

## Impact

- iOS safety/UI/state: blind and volunteer in-run screens, shared emergency coordinator, location snapshot handling, AppState/realtime coordination, TTS, VoiceOver, Mock state, and session cleanup.
- Contracts: `/api/emergency/trigger`, structured trigger response/errors, both-role notification delivery, SMS-notification semantics, recovery after reconnect/relaunch, and no order-status mutation.
- Dependencies: requires `complete-realtime-fallback-and-notifications` and `enable-live-escort-location-and-track-summary`; the latter supplies fresh GCJ-02 service location and background continuity.
- Documentation/release: `AGENTS.md`, maintained docs, safety copy, failure behavior, privacy, and supervised real-device acceptance. The OpenAPI and WebSocket contracts live in the backend repository since 2026-07-28, so this change files the gaps there instead of editing them here (tasks 2.3 / 2.4) — those two are not gates on iOS delivery. Supervised real-device acceptance still is, and remains outstanding (task 6.6).
