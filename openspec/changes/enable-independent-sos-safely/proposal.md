> # ⛔ 状态：本版不交付（DEFERRED — NOT SHIPPING IN THIS RELEASE）
>
> **决策日期**：2026-07-31 ｜ **决策人**：项目负责人 ｜ **代码进度**：0/28，iOS 侧完全未启动
>
> **不交付的原因**
>
> 1. **依赖的后端语义未澄清**。本提案的核心承诺——「只有在后端确认短信真的送达后才展示『联系人已收到短信』」——目前无法兑现：`design.md` 里 7 处 `需要人工确认` 全部未答复，其中最关键的是 `EMERGENCY_CONTACT_NOTIFIED` 到底代表短信被服务商受理、已投递到手机，还是仅仅入队。在这条语义定死之前，任何 SOS UI 都可能对用户过度承诺救援已经发生。
> 2. **本 release 不宣称求助能力**。与 `plan.md:76` 的人工确认项一致：当前 release 隐藏求助入口，不宣称真实求助能力；`POST /api/emergency/trigger` 仅作为后端合同探针保留。`AGENTS.md` 第 6/10 节同样规定本版必须隐藏紧急入口。
>
> **当前代码事实（与本提案一致，无需改动）**
>
> - `blindRun/Core/Models/OrderModels.swift:150` `showsEmergencyPlaceholder` 硬编码 `return false`，两个角色都不展示紧急入口。
> - `/api/emergency/trigger` 只存在于 `blindRun/Core/MockAPIClient.swift:337`，真实 `APIClient` 无调用。
> - WebSocket 的 emergency 事件只收不发（由 `AppRealtimeCoordinator` 按稳定事件标识路由，但不实现任何功能动作）。
>
> **本提案不归档、tasks 不删除**：28 项任务全部保留，作为重启时的现成清单。
>
> **重启的前置条件**（全部满足才可重新排期）
>
> 1. 后端书面答复 `design.md` 中全部 `需要人工确认`，其中 `EMERGENCY_CONTACT_NOTIFIED` 的投递语义为**硬前置**。
> 2. 产品 / 合规批准严格无 GPS 阻断策略（`design.md:43`），以及最终的求助文案与责任边界。
> 3. `enable-live-escort-location-and-track-summary` 已交付并通过双真机验收——本提案的新鲜真实 GCJ-02 坐标依赖同行会话的定位链路。
> 4. 二次确认文案必须与 `AGENTS.md` 第 10 节的强制原文逐字一致。
>
> 在以上条件满足前，**不要**依据本提案实现任何 SOS UI、不要打开 `showsEmergencyPlaceholder`、也不要在真实 `APIClient` 中新增 `/api/emergency/trigger` 调用。

## Why

The backend accepts emergency triggers from blind-runner and volunteer tokens and owns emergency-contact SMS escalation, but the current iOS release intentionally hides both emergency entries. The approved scope is now narrower and safer than the earlier independent-SOS proposal: only the two participants of an `IN_PROGRESS` run may initiate an order-associated SOS, and the app must not claim SMS success until a backend event confirms it.

The existing change ID is retained for continuity, but its former independent blind-runner capability is replaced by a dual-role in-run safety flow.

## What Changes

- **BREAKING** Remove the proposed always-reachable/no-order blind SOS and enable an SOS entry only for the associated blind runner and volunteer while canonical order status is `IN_PROGRESS`.
- Require the exact project-mandated second-confirmation text before every trigger.
- Submit the owned `orderId` and a fresh real GCJ-02 GPS coordinate from the live escort session to `POST /api/emergency/trigger`.
- Treat trigger success as a separate emergency event keyed by backend `eventId`; never synthesize or mutate `RunOrderStatus`.
- Present “联系人已收到短信” only after an event-ID-matching backend contact-notification message whose contract confirms successful SMS notification; trigger acknowledgement alone shows only submitted/processing state.
- Route the same pending, failed, contact-notified, and resolved safety state across both role experiences through the app-lifetime realtime coordinator.
- Keep SMS delivery, reverse geocoding, emergency-contact selection, CS escalation, schedulers, and rescue operations backend-owned.

## Capabilities

### New Capabilities

- `in-run-dual-role-sos`: Defines dual-role `IN_PROGRESS` eligibility, exact confirmation, required order/current-GPS association, event state, backend-confirmed SMS copy, accessibility, and unchanged order lifecycle.

### Modified Capabilities

- `formal-dispatch-service-flow`: Replaces the current hidden emergency requirement with the approved `IN_PROGRESS`-only dual-role entry.
- `backend-api-contract`: Defines both-role trigger authorization, structured trigger result, GCJ-02 fields, event recovery, and typed contact-notified/resolved WebSocket messages for both participants.
- `global-realtime-notification-handling`: Routes emergency events by event/order/role independently of screen lifetime.

## Impact

- iOS safety/UI/state: blind and volunteer in-run screens, shared emergency coordinator, location snapshot handling, AppState/realtime coordination, TTS, VoiceOver, Mock state, and session cleanup.
- Contracts: `/api/emergency/trigger`, structured trigger response/errors, both-role notification delivery, SMS-notification semantics, recovery after reconnect/relaunch, and no order-status mutation.
- Dependencies: requires `complete-realtime-fallback-and-notifications` and `enable-live-escort-location-and-track-summary`; the latter supplies fresh GCJ-02 service location and background continuity.
- Documentation/release: `AGENTS.md`, maintained docs, OpenAPI, WebSocket protocol, safety copy, failure behavior, privacy, and supervised real-device acceptance must be updated before UI enablement.
