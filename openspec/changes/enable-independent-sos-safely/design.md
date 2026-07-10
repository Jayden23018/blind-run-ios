## Context

The current safety module contains the required confirmation copy and placeholder UI, but every order status returns `showsEmergencyPlaceholder = false`; action methods only announce that emergency is unavailable. The backend now accepts a blind JWT at `POST /api/emergency/trigger`, permits all request fields to be omitted, returns an event ID with `PENDING` status, applies location degradation and cooldown, alerts an associated volunteer, and escalates to emergency contacts through backend schedulers.

This change formally enables SOS under the exception already anticipated by `AGENTS.md`: a dedicated safety change must define GPS behavior, notification, failure copy, compliance language, and acceptance tests first. It depends on the app-lifetime realtime coordinator proposed by `complete-realtime-fallback-and-notifications`.

## Goals / Non-Goals

**Goals:**

- Make SOS reachable for every authenticated blind-role user, including users without an order or without completed booking prerequisites.
- Support optional order association and optional current GPS without blocking no-location SOS.
- Present a durable event-based safety state using backend event ID/status and real-time follow-up.
- Give an associated volunteer a bounded, confirmable response flow.
- Preserve order status, location privacy, accessibility, and honest responsibility language.

**Non-Goals:**

- Implementing CS/admin rescue workflows, SMS, Redis, AMap reverse geocoding, escalation schedulers, emergency-service dispatch, automatic phone calls, background APNs, live-track sharing, or virtual numbers.
- Representing emergency as an order status or promising that police, ambulance, or a rescuer has been dispatched.

## Decisions

### 1. SOS is independent of profile, identity, contact, order, and location gates

A signed-in user with active role `BLIND` can reach the SOS action from every blind-role root flow, including profile/identity/contact onboarding and home/order screens. Missing identity approval, missing emergency contact, no active order, or denied location must not disable the action. Authentication remains required because the backend requires a blind JWT.

Alternative considered: show SOS only during `DRIVER_EN_ROUTE`, `DRIVER_ARRIVED`, and `IN_PROGRESS`. That excludes the newly implemented independent SOS use case.

### 2. Keep confirmation exact until compliance approves a separate independent copy

Every trigger requires a second confirmation and, under the current highest-priority rule, uses exactly:

`是否确认进入求助状态？确认后，本次服务将标记为异常，系统会记录当前订单状态。`

`需要人工确认`: this wording references a service/order and is semantically inaccurate for independent SOS. Before public release, the product/compliance owner must either approve it for both contexts or approve a separate no-order copy and update `AGENTS.md`; implementation must not silently change it.

Alternative considered: invent a clearer no-order sentence now. That would violate the exact-copy rule.

### 3. Build an event-based EmergencyCoordinator

An `EmergencyCoordinator`, integrated with the app-lifetime realtime coordinator, will own trigger loading/cooldown and the current user-visible event state keyed by `eventId`. It will not own or mutate `RunOrderStatus`. A successful trigger enters `pending`; subsequent typed backend/WS events may mark contact-notified, escalated, resolved, false-alarm, or other documented states.

The latest event ID/status may be persisted as non-secret recovery metadata, but it must be scoped to the authenticated user ID and cleared on logout, account deletion, session expiration, or user change. A role switch may retain it only for the same authenticated account and must not present it outside the blind-role flow. Public enablement requires a documented backend status-recovery mechanism after relaunch or reconnect. `需要人工确认`: the supplied contract does not identify a blind-user `GET` endpoint for event recovery.

Alternative considered: show “sent” once and forget the event. This is unsafe because users cannot distinguish pending, escalated, or resolved state after navigation.

### 4. Associate only eligible service orders and never mutate them

At confirmation time, the coordinator may attach `orderId` only when the blind user has an order in `DRIVER_EN_ROUTE`, `DRIVER_ARRIVED`, or `IN_PROGRESS`. Independent SOS omits `orderId`. `PENDING_MATCH`, `PENDING_ACCEPT`, `REMATCHING`, and terminal orders are not attached unless the backend contract is explicitly expanded.

Trigger success records an emergency event; it does not synthesize an `emergency` status, alter local order status, or stop normal order polling.

### 5. Submit the best available current location without gating

If location is authorized and a current device coordinate is available, the request includes `gpsLat/gpsLng`. Otherwise both are omitted and the request proceeds. The confirmation/result UI reports whether precise device location was included and explains that the server will use available fallback information, without claiming a precise address or exposing raw coordinates.

Reverse geocoding, fallback selection, SMS content, and escalation remain backend-owned. iOS does not call AMap geocoding as a prerequisite for SOS.

Alternative considered: block until GPS resolves. Delay or permission denial must not prevent an emergency event.

### 6. Cooldown and failures remain backend authoritative

Duplicate taps are disabled while a request is in flight. A backend cooldown response retains the existing event state and disables retrigger for the documented retry interval. Offline/network failure remains an unsent state with prominent visible and spoken copy; the app never says the request was received without a successful structured response.

`需要人工确认`: stable cooldown error code, retry field/header, whether repeated triggers return the existing event ID, and the allowed retry policy.

### 7. Volunteer responses require their own confirmations

An associated volunteer receives a high-priority `EMERGENCY_VOLUNTEER_ALERT` routed by event ID. The UI presents approved message/location text but no blind-user raw coordinate, live marker, direction, route, or track. `NEED_HELP` and `FALSE_ALARM` each require explicit confirmation before `PUT /api/emergency/{eventId}/volunteer-response?action=...`; timeout is displayed but escalation remains backend-owned.

The volunteer cannot resolve an independent event with no associated order/volunteer alert.

### 8. Safety copy never overpromises rescue

Success copy says the event was recorded and is being processed. Contact-notified copy is shown only after the corresponding backend event. Escalation/resolution language is driven by typed backend state. Offline or failed requests clearly state that SOS was not sent and provide the product-approved offline safety guidance.

`需要人工确认`: compliance owner must approve success, no-location, offline, cooldown, contact-notified, escalated, false-alarm, and resolved copy plus whether any external emergency number may be referenced.

## Risks / Trade-offs

- [Risk] Independent SOS confirmation copy incorrectly mentions an order. → Require compliance decision and `AGENTS.md` update before public enablement.
- [Risk] App relaunch loses event state or restores another account's event. → Block release until a documented recovery contract exists, key persisted metadata by user ID, and clear it during session cleanup.
- [Risk] Network failure is mistaken for successful rescue. → Gate success strictly on structured `success/eventId/status` and use explicit unsent copy.
- [Risk] Volunteer false-alarm response suppresses escalation incorrectly. → Require second confirmation and backend authorization/status validation.
- [Risk] Emergency coordinates leak to UI or logs. → Keep raw coordinates request-only and test rendered/accessibility/log output.
- [Risk] SOS entry disrupts voice-first primary tasks. → Use a consistent, always-reachable safety region after primary state/actions with a 64pt target and deterministic VoiceOver order.

## Migration Plan

1. Complete the global realtime coordinator change and confirm all missing emergency contracts/copy.
2. Update `AGENTS.md`, plan/product/scope/flow/page/data/architecture/accessibility docs, OpenAPI, and WebSocket protocol together.
3. Add event/request/response/cooldown/recovery models, user-scoped recovery cleanup, and Mock safety behavior while UI remains disabled.
4. Implement EmergencyCoordinator, independent blind entry, active-order association, location degradation, and volunteer response.
5. Add exact-copy, failure, privacy, accessibility, and no-order-status-mutation tests.
6. Run strict docs/OpenSpec validation, cloud contract probes, and supervised dual-device safety acceptance.
7. Enable the release-facing SOS entry only after contract, compliance, and acceptance evidence is recorded.

Rollback disables entry presentation while preserving event parsing and backend contract probes. It must not delete or alter already recorded backend emergency events.

## Open Questions

- `需要人工确认`: What no-order confirmation copy is approved, or is the current exact order-oriented copy approved unchanged?
- `需要人工确认`: What blind-user event-status recovery endpoint or equivalent mechanism is available after relaunch/reconnect?
- `需要人工确认`: What are the exact cooldown code, retry semantics, repeat-trigger response, and state enum?
- `需要人工确认`: Which typed WebSocket messages represent pending, contact-notified, escalated, resolved, and false-alarm outcomes?
- `需要人工确认`: What safety/compliance and offline guidance copy is approved for release?
