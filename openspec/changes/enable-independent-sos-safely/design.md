## Context

（本节描述的是变更**开工前**的基线，不是现状；`showsEmergencyPlaceholder` 已随交付删除，全仓 0 命中。）

The app already contains shared emergency button/confirmation components and placeholder actions, but `showsEmergencyPlaceholder` is always false and both role actions only announce that the feature is unavailable. The live backend accepts `orderId`, `gpsLat`, and `gpsLng`, but its current Swagger response is still generic. Existing WebSocket models include some blind contact/resolution messages and a volunteer alert, yet they do not establish that both initiating roles receive event-ID-matching SMS confirmation.

This revision removes the previous independent blind SOS design. Eligibility is deliberately limited to the two participants of a canonical `IN_PROGRESS` order, where the live escort session already maintains real location.

## Goals / Non-Goals

**Goals:**

- Give both associated roles the same accessible in-run SOS action.
- Require exact second confirmation and submit the owned order plus current real GCJ-02 location.
- Separate emergency event state from order state.
- Distinguish trigger acknowledgement from the backend's later contact-notification event, and let neither become a delivery claim (Decision 5).
- Preserve event delivery across navigation, lock/background operation, reconnect, and relaunch where the backend recovery contract permits.

**Non-Goals:**

- Independent/no-order SOS, pre-service SOS, automatic SOS, fall detection, client-side SMS, CS/admin UI, emergency-service dispatch, automatic calls, or backend implementation.
- Volunteer `FALSE_ALARM` response UI, permanently: the backend answers a volunteer `action=FALSE_ALARM` with 403 `EMERGENCY_VOLUNTEER_CANNOT_DISMISS`, because in a one-to-one escort the companion is who a victim may need protection from. Only the blind runner (`PUT /api/emergency/{id}/cancel`) and customer service can close an event. The volunteer's single `NEED_HELP` acknowledgement (`PUT /api/emergency/{id}/volunteer-response`, `EmergencyCoordinator.acknowledgeAsVolunteer`) is in scope and shipped.
- Claiming that police, ambulance, a rescuer, or SMS handset delivery is guaranteed beyond the exact backend-confirmed semantics.

## Decisions

### 1. Eligibility is exactly owned IN_PROGRESS participation

The SOS action is visible only when canonical order detail is `IN_PROGRESS` and the active authenticated role is the associated `BLIND` or `VOLUNTEER` participant. It is hidden in `PENDING_MATCH`, `PENDING_ACCEPT`, `DRIVER_EN_ROUTE`, `DRIVER_ARRIVED`, `REMATCHING`, and terminal states. What "hidden" governs is the *order-associated cloud path*: the blind-runner home keeps a persistent bottom bar in every state, but outside `IN_PROGRESS` it degrades to a purely local phone call that reaches no emergency endpoint and says so (`BlindHomeSOSMode.resolve`).

Eligibility is checked again in the coordinator immediately before sending. WebSocket or local stale state never expands eligibility. Role switching remains blocked by the existing active-order rule.

### 2. Use the exact required confirmation text for both roles

Every trigger uses exactly:

`是否确认进入求助状态？确认后，本次服务将标记为异常，系统会记录当前订单状态。`

Cancel sends no request. Confirm disables duplicate submission until a structured result or failure is received. The same copy is used for both roles because the approved scope always has an active service order.

### 3. Require order ID and a fresh real GCJ-02 location snapshot

The request includes the owned `IN_PROGRESS` order ID and a current real coordinate normalized by the live escort change's single GCJ-02 boundary. On confirmation, the coordinator asks the active location session for its latest valid sample and may request a fresh one-shot update if needed.

If no valid real sample can be obtained, the request is not sent and the app states visibly and audibly that SOS was not submitted because current location is unavailable, with Settings/retry guidance. Demo fallback coordinates are forbidden. `需要人工确认`: product/safety must approve this strict GPS gate because the backend technically supports location degradation when GPS is omitted.

### 4. Model SOS as a separate event coordinator

An `EmergencyCoordinator`, integrated with `AppRealtimeCoordinator`, owns one active order-associated emergency event keyed by `eventId`, initiating role/user, order ID, submitted location state, and backend status. It never owns or mutates `RunOrderStatus`; normal order polling and finish/cancel permissions continue from canonical detail.

Only a structured successful response containing `success`, `eventId`, and `status` enters submitted/processing state. Network failure, timeout, decoding failure, and backend rejection remain explicit unsent/failed states.

### 5. Never show SMS success copy at all

> **2026-08-01 订正**：本决策原文是「按 `eventId` 匹配到后端通知后才展示『联系人已收到短信』」。
> 读后端实现后该条件在任何时刻都不成立，规则退化为它的守卫含义 —— **该文案永不展示**。
> 下面是订正后的口径，`specs/in-run-dual-role-sos/spec.md` 的
> “The app never claims an emergency SMS was delivered” 与之一致。

Trigger success may say only that the request was recorded and is being processed. No state ever shows or speaks that a contact received an SMS: the backend emits `EMERGENCY_CONTACT_NOTIFIED` synchronously inside the trigger transaction (`EmergencyService.java:370-373`) while the SMS goes out afterwards on an `AFTER_COMMIT` async listener (`EmergencyContactNotifier.java:60-62`), and a send failure is broadcast only to customer service (`:126-135`), never corrected back to the blind runner. Nothing in the flow proves receipt, so the app substitutes its own progressive-tense copy for the backend body and TTS text whenever it renders an emergency event.

Event-ID matching is unavailable regardless: the message arrives inside an `APP_NOTIFICATION` envelope carrying neither `eventId` nor `orderId` (`NotificationService:93-99`), so routing falls back to order association plus message identity. That fallback is acceptable only because the copy itself promises nothing.

Both roles render the same client-owned copy through the shared coordinator, so nothing here is gated on which socket the backend notifies. A delivery claim may be introduced only by a later change, after the backend defines an outcome that actually proves handset delivery and product/compliance approve the wording.

### 6. Preserve state safely across lifecycle changes

Foreground presentation and TTS are routed at app lifetime. The latest non-secret event ID/order/status metadata may be retained per authenticated user and cleared on logout, deletion, session expiration, user change, terminal event, or order disassociation. After reconnect/relaunch, retained state is not presented as authoritative until recovered from a documented backend endpoint or event replay.

### 7. Safety presentation is accessible and status neutral

Both role buttons use at least a 64-point target, clear accessibility label/hint, exact confirmation, visible progress/result, VoiceOver announcement, and TTS. Blind-runner “重复当前状态” includes the latest authoritative SOS state after the canonical order status without replacing it.

Failure and pending copy never promises rescue or SMS. Contact-notified copy appears only under the rule above. Emergency event transitions never enable/disable finish or cancellation except for temporary duplicate-submit protection on the SOS action itself.

## Risks / Trade-offs

- [Risk] Strict GPS gating delays SOS when location is unavailable. → Require safety approval, use the already-running background session plus a bounded fresh request, and provide immediate unsent/retry/Settings feedback.
- [Risk] Backend acknowledgement is mistaken for SMS success. → Maintain separate submitted and contact-notified states keyed by event ID.
- [Risk] “已收到短信” overstates provider semantics. → Block that exact copy permanently and override the backend-supplied body with client-owned progressive-tense copy (Decision 5).
- [Risk] A volunteer press alerts the volunteer instead of the blind runner. → Resolved upstream by backend `a5ba523` (SOS-1): the event is keyed to the order's blind party and the source is recorded as `TriggerType.VOLUNTEER_BUTTON`, so escalation reaches the blind runner's emergency contacts. The volunteer sees only their own trigger result through the shared coordinator; no recovery contract exists for either role, so nothing survives a relaunch.
- [Risk] A volunteer mis-presses and cannot undo it. → Accepted deliberately: the volunteer has no dismiss path by design (403 `EMERGENCY_VOLUNTEER_CANNOT_DISMISS`), so the entry is kept out of the thumb zone as a floating shield in the map corner rather than mixed into the action buttons.
- [Risk] Emergency state changes order lifecycle locally. → Keep a separate coordinator and test every order status/permission remains backend-driven.
- [Risk] Stale event metadata crosses accounts. → Scope by authenticated user/order and clear on every session boundary.
- [Risk] Location leaks to UI/logs. → Keep coordinates request-only, reuse typed GCJ-02 value objects, and assert absence from logs/accessibility text.

## Migration Plan

1. Complete and validate global realtime plus live escort/background/GCJ-02 dependencies.
2. Freeze structured trigger response/errors, both-role authorization and follow-up, SMS semantics, and recovery contract.
3. Update `AGENTS.md`, maintained docs, OpenAPI, WebSocket protocol, compliance copy, and release risks.
4. Add request/response/event models and Mock event state while UI remains hidden.
5. Implement the shared coordinator, strict eligibility/GPS snapshot, exact confirmation, and role-specific presentation.
6. Add client-owned emergency copy that never claims delivery, session cleanup, accessibility, and failure tests. (Recovery was dropped from this step once the backend turned out to expose no recovery endpoint or replay.)
7. Run supervised dual-device real-backend safety acceptance before enabling Demo/Production UI.

Rollback hides both entries while retaining safe parsing and preserving already-recorded backend emergency events.

## Open Questions

原 5 条的处置见 `proposal.md` 顶部状态块；此处逐条标注，**未标「已答」的仍然是待答**。

- **仍待答** `需要人工确认`: approve or reject strict no-GPS blocking versus backend location-degradation submission. —— 未收到产品/安全的书面批准，交付时按最严格的一侧默认：`EmergencyCoordinator.allowsSubmissionWithoutLocation = false`，批准后翻转这一个常量即可，不牵动其它 SOS 规则。
- **已答（读后端实现）** structured trigger success/error/cooldown schemas and authoritative event status enum. —— `{success,eventId,status}`（`EmergencyController.java:34-38`）、`EmergencyStatus` 全集、429 `TOO_MANY_REQUESTS` + `retryAfterSeconds`（`GlobalExceptionHandler.java:218-231`）。**后端 `api_spec.yaml` 那一段仍只写 `type: object`**，补 schema 的请求已投递（tasks 2.3）。
- **已答（对 iOS 而言）** does contact notification prove provider acceptance or handset delivery? —— 都不证明：事件在短信尝试之前同步发出，失败只广播给客服。因此「联系人已收到短信」在 iOS 侧**永不展示**，法务口径不再是 iOS 的阻塞项（Decision 5）。
- **部分已答** which contact-notified/resolved messages are sent to a volunteer who initiates or participates in the event? —— 事件归属已由后端 `a5ba523` 定死在订单的盲人方，志愿者代触发用 `TriggerType.VOLUNTEER_BUTTON` 标注；志愿者收到的告警是 `EMERGENCY_VOLUNTEER_ALERT`（`EmergencyCoordinator.volunteerAlert`）。**后端是否也向志愿者 socket 投递 contact-notified / resolved 仍未书面确认**，但不影响 UI：两侧渲染的都是客户端自有文案，不承诺任何送达。
- **已答（答案是「没有」）** what participant event-recovery endpoint or replay exists after reconnect/relaunch? —— 后端两者都没有。因此 iOS **不持久化**任何事件元数据，进程重启即清空，「不得把未经后端确认的状态当权威呈现」自动成立。
