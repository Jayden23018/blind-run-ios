## Context

`LocationService` currently uses `CLLocationManager` with best accuracy and a 10-meter distance filter, but there is no order-scoped cadence or background execution policy. `WebSocketService` sends location messages and runs a 30-second heartbeat only for blind users; its minimum-send check can drop a message when timers collide. The app decodes volunteer-to-blind locations but not the reverse direction. AMap supports point annotations but not route polylines. The canonical local OpenAPI does not yet include the live backend's typed track endpoint.

The backend team has confirmed GCJ-02 as the intended wire coordinate system and is still changing coordinate-related behavior. Implementation must therefore establish one explicit normalization boundary and must not ship cloud reporting until input/output and existing-track semantics are frozen.

## Goals / Non-Goals

**Goals:**

- Send a 30-second heartbeat and five-second service-session location update for both roles.
- Preserve `IN_PROGRESS` recording while locked/backgrounded, within iOS runtime limits.
- Show the associated participant's live position in eligible states and surface separation alerts accessibly.
- Fetch and render a completed blind-runner route with distance, duration, and average pace.
- Decode the volunteer track but restrict it to approved anomaly comparison rather than presenting it as the user's route.

**Non-Goals:**

- In-app turn-by-turn navigation, public/live track sharing outside the two order participants, background APNs, fall detection, geofencing, server sampling/storage changes, or backend source code.
- Guaranteeing continued recording after the user force-quits the app, the OS terminates it, device power/network/location is unavailable, or the user revokes permission.
- Inventing a client-only anomaly threshold that can drift from backend configuration.

## Decisions

### 1. Introduce an order-scoped LiveEscortSessionCoordinator

A `LiveEscortSessionCoordinator`, owned at app lifetime and fed by canonical order refreshes, controls heartbeat, location cadence, background capture, peer samples, and cleanup. It uses `AppRealtimeCoordinator` outputs rather than subscribing directly to `WebSocketService`.

The service-session location cadence starts when an associated order reaches `DRIVER_EN_ROUTE`, continues through `DRIVER_ARRIVED` and `IN_PROGRESS`, and stops immediately on `COMPLETED`, `CANCELLED`, `REMATCHING`, `NO_VOLUNTEER`, logout, account change, role-token replacement without the same associated order, or explicit WebSocket teardown. Background continuation is mandatory only during `IN_PROGRESS`; pre-service states may report while the app is active and immediately after reconnect.

### 2. Use 30-second PING and five-second LOCATION_UPDATE for both roles

Each connected role sends `PING` every 30 seconds. During an eligible live escort session, the coordinator sends the most recent valid location every five seconds and sends one immediately on session start/reconnect. Location updates are cadence-based even when the device has not moved so backend liveness/track sampling does not depend on `CLLocationManager` callback frequency.

Outgoing messages use a small serialized queue that preserves the 500 ms minimum interval rather than silently dropping a heartbeat or location when timers coincide. `PONG` updates heartbeat health; documented consecutive missing responses cause reconnect, without changing order state. `需要人工确认`: production `/ws/volunteer` must accept `PING` and return `PONG` before enabling the volunteer heartbeat.

### 3. Continue location during lock/background only for an active run

The target enables the iOS `location` background mode and appropriate location usage descriptions. When an order enters `IN_PROGRESS`, `LocationService` uses fitness-oriented continuous updates, background updates, a visible system background-location indicator where applicable, and a deliberate accuracy/distance policy. It disables background updates and returns to the normal policy when the run ends.

The app explains background collection before service begins. Permission denial or later revocation produces visible/TTS guidance and a degraded recording warning; it does not synthesize points or silently use demo coordinates. Real-device validation covers locking both devices and backgrounding each role for a sustained interval.

### 4. Normalize coordinates exactly once at the network boundary

Internal location samples carry coordinate-system provenance. Raw device coordinates are converted exactly once by a centralized `BackendCoordinateNormalizer` into GCJ-02 before WebSocket upload. Incoming peer coordinates and track points are interpreted as GCJ-02 and passed directly to AMap. Distance/pace comparisons use coordinates expressed in the same system.

No feature ViewModel performs ad hoc conversion. Fixtures around known Chinese locations test conversion direction and prevent double conversion. `需要人工确认`: backend must freeze whether every location input/output—including REST fallback, historical track points, order start coordinates, and WebSocket messages—is GCJ-02 and how pre-migration stored coordinates are identified.

### 5. Present peer location only to the associated order participants

During `DRIVER_EN_ROUTE`, `DRIVER_ARRIVED`, and `IN_PROGRESS`, the blind-runner map may display the associated volunteer marker and the volunteer map may display the associated blind-runner marker. Samples must match the active order, pass coordinate validation, and satisfy the documented freshness window. Stale markers are hidden or explicitly marked unavailable.

Visible text and accessibility labels identify the role and freshness without speaking raw latitude/longitude. Peer samples are in-memory only and are cleared when the associated session ends or identity changes.

### 6. Treat separation alerts as high-priority events, not order states

The backend remains authoritative for separation detection. A typed `ESCORT_DISTANCE_ALERT` is routed by stable event identity and presented immediately with equivalent banner, VoiceOver, and TTS. Repeated delivery of the same alert is deduplicated; distinct alerts are preserved. The client does not create an emergency event, cancel/finish the order, or claim that rescue has been dispatched.

### 7. Use the blind-runner track as the completed route

After `COMPLETED`, either participant may request `GET /api/orders/{id}/track`. `OrderTrackResponse` decodes ordered blind and volunteer `TrackPoint` arrays plus per-role `TrackStats`. The primary summary renders:

- blind track polyline titled "本次路线";
- blind distance, duration, and average pace;
- explicit empty/partial data states; and
- textual/TTS equivalents independent of visual map inspection.

The volunteer track is never labeled as "本次路线" and is not shown as a second default route. It is retained for anomaly comparison only. A user-facing discrepancy flag requires either a backend-provided assessment/threshold or a product-approved versioned comparison policy. Until that contract is frozen, the app may decode/test volunteer data but must not invent or display an abnormality conclusion.

### 8. Add AMap polyline support without moving business logic into views

The map bridge gains stable-ID polyline overlays and viewport fitting for the primary route. Track preparation, empty-state selection, summary formatting, and anomaly comparison remain in models/ViewModels. The route map is auxiliary for VoiceOver; the summary text and "重复当前状态" provide the equivalent experience.

## Risks / Trade-offs

- [Risk] Background GPS drains battery. → Scope enhanced background capture to `IN_PROGRESS`, tune accuracy/distance filters, stop deterministically, and measure on both release devices.
- [Risk] iOS suspends or terminates the process. → Use background location correctly, expose gaps honestly, reconnect immediately when execution resumes, and do not promise force-quit continuity.
- [Risk] GCJ-02 is converted twice or mixed with legacy data. → Centralize provenance/normalization and block cloud enablement until the backend freezes all coordinate fields and migration behavior.
- [Risk] Five-second location and 30-second ping collide with the send limiter. → Serialize queued sends instead of dropping them.
- [Risk] Peer coordinates leak outside the associated order. → Key by order/user, clear on lifecycle changes, avoid logs/persistence, and test cross-account/order isolation.
- [Risk] Client anomaly results disagree with backend separation configuration. → Require a versioned threshold/backend assessment before user-facing anomaly copy.
- [Risk] Track endpoint returns partial/null statistics. → Model null/empty fields and show honest unavailable copy rather than calculating from demo data.

## Migration Plan

1. Freeze and document GCJ-02, heartbeat, location envelopes, separation identity, track schemas, and anomaly policy.
2. Update canonical docs/OpenAPI/WebSocket contract and privacy/release risks.
3. Add typed coordinate provenance, serialized send queue, heartbeat health, and service-session coordinator behind disabled UI.
4. Add five-second foreground reporting, then `IN_PROGRESS` background capture and deterministic cleanup.
5. Add reverse peer-location decoding/presentation and separation alerts.
6. Add track models, Mock responses, AMap polylines, and accessible completed summary.
7. Validate on Mock, focused tests, cloud probes, and locked/backgrounded dual devices.

Rollback disables live-session/background reporting and peer/track presentation while preserving existing dispatch location reporting and canonical order flows.

## Open Questions

- `需要人工确认`: when will the backend GCJ-02 change be frozen, and are all order, REST, WebSocket, and historical track coordinates consistently tagged/converted?
- `需要人工确认`: does `/ws/volunteer` accept `PING` and return the same `PONG` shape as `/ws/blind`?
- `需要人工确认`: what is the canonical production separation-alert envelope and stable event ID?
- `需要人工确认`: will the backend expose a versioned anomaly threshold/result, or what exact product-approved client comparison rule should be used for the volunteer track?
- `需要人工确认`: what are track endpoint error/no-data semantics before completion and for legacy completed orders?
