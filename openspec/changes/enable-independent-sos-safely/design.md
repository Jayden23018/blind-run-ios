## Context

The app already contains shared emergency button/confirmation components and placeholder actions, but `showsEmergencyPlaceholder` is always false and both role actions only announce that the feature is unavailable. The live backend accepts `orderId`, `gpsLat`, and `gpsLng`, but its current Swagger response is still generic. Existing WebSocket models include some blind contact/resolution messages and a volunteer alert, yet they do not establish that both initiating roles receive event-ID-matching SMS confirmation.

This revision removes the previous independent blind SOS design. Eligibility is deliberately limited to the two participants of a canonical `IN_PROGRESS` order, where the live escort session already maintains real location.

## Goals / Non-Goals

**Goals:**

- Give both associated roles the same accessible in-run SOS action.
- Require exact second confirmation and submit the owned order plus current real GCJ-02 location.
- Separate emergency event state from order state.
- Distinguish trigger acknowledgement from backend-confirmed emergency-contact SMS notification.
- Preserve event delivery across navigation, lock/background operation, reconnect, and relaunch where the backend recovery contract permits.

**Non-Goals:**

- Independent/no-order SOS, pre-service SOS, automatic SOS, fall detection, client-side SMS, CS/admin UI, emergency-service dispatch, automatic calls, or backend implementation.
- Volunteer `NEED_HELP`/`FALSE_ALARM` response UI unless separately approved; both roles in this change are initiators/observers of the order-associated event.
- Claiming that police, ambulance, a rescuer, or SMS handset delivery is guaranteed beyond the exact backend-confirmed semantics.

## Decisions

### 1. Eligibility is exactly owned IN_PROGRESS participation

The SOS action is visible only when canonical order detail is `IN_PROGRESS` and the active authenticated role is the associated `BLIND` or `VOLUNTEER` participant. It is hidden in `PENDING_MATCH`, `PENDING_ACCEPT`, `DRIVER_EN_ROUTE`, `DRIVER_ARRIVED`, `REMATCHING`, and terminal states.

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

### 5. Gate SMS success copy on a matching backend notification

Trigger success may say only that the request was recorded and is being processed. “联系人已收到短信” is shown and spoken only after a typed contact-notified event matches the active `eventId` and `orderId` and is delivered to the initiating/associated role according to the frozen contract.

`需要人工确认`: the backend must define whether `EMERGENCY_CONTACT_NOTIFIED` means SMS accepted by the provider, delivered to the handset, or merely queued. If it does not prove receipt, product/compliance must approve truthful alternative copy; iOS must not overstate delivery.

Both the blind runner and volunteer need a documented event update. If the backend currently emits contact notification only to the blind socket, volunteer-triggered SMS confirmation remains blocked.

### 6. Preserve state safely across lifecycle changes

Foreground presentation and TTS are routed at app lifetime. The latest non-secret event ID/order/status metadata may be retained per authenticated user and cleared on logout, deletion, session expiration, user change, terminal event, or order disassociation. After reconnect/relaunch, retained state is not presented as authoritative until recovered from a documented backend endpoint or event replay.

### 7. Safety presentation is accessible and status neutral

Both role buttons use at least a 64-point target, clear accessibility label/hint, exact confirmation, visible progress/result, VoiceOver announcement, and TTS. Blind-runner “重复当前状态” includes the latest authoritative SOS state after the canonical order status without replacing it.

Failure and pending copy never promises rescue or SMS. Contact-notified copy appears only under the rule above. Emergency event transitions never enable/disable finish or cancellation except for temporary duplicate-submit protection on the SOS action itself.

## Risks / Trade-offs

- [Risk] Strict GPS gating delays SOS when location is unavailable. → Require safety approval, use the already-running background session plus a bounded fresh request, and provide immediate unsent/retry/Settings feedback.
- [Risk] Backend acknowledgement is mistaken for SMS success. → Maintain separate submitted and contact-notified states keyed by event ID.
- [Risk] “已收到短信” overstates provider semantics. → Block that exact copy until backend/compliance confirms what the notification proves.
- [Risk] Volunteer-triggered events do not receive follow-up. → Require both-role WebSocket/recovery contract before enabling volunteer UI.
- [Risk] Emergency state changes order lifecycle locally. → Keep a separate coordinator and test every order status/permission remains backend-driven.
- [Risk] Stale event metadata crosses accounts. → Scope by authenticated user/order and clear on every session boundary.
- [Risk] Location leaks to UI/logs. → Keep coordinates request-only, reuse typed GCJ-02 value objects, and assert absence from logs/accessibility text.

## Migration Plan

1. Complete and validate global realtime plus live escort/background/GCJ-02 dependencies.
2. Freeze structured trigger response/errors, both-role authorization and follow-up, SMS semantics, and recovery contract.
3. Update `AGENTS.md`, maintained docs, OpenAPI, WebSocket protocol, compliance copy, and release risks.
4. Add request/response/event models and Mock event state while UI remains hidden.
5. Implement the shared coordinator, strict eligibility/GPS snapshot, exact confirmation, and role-specific presentation.
6. Add backend-confirmed SMS state, recovery, cleanup, accessibility, and failure tests.
7. Run supervised dual-device real-backend safety acceptance before enabling Demo/Production UI.

Rollback hides both entries while retaining safe parsing and preserving already-recorded backend emergency events.

## Open Questions

- `需要人工确认`: approve or reject strict no-GPS blocking versus backend location-degradation submission.
- `需要人工确认`: structured trigger success/error/cooldown schemas and authoritative event status enum.
- `需要人工确认`: does contact notification prove provider acceptance or handset delivery, and is “联系人已收到短信” legally/product accurate?
- `需要人工确认`: which contact-notified/resolved messages are sent to a volunteer who initiates or participates in the event?
- `需要人工确认`: what participant event-recovery endpoint or replay exists after reconnect/relaunch?
