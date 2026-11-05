## Context

`LocationService` currently uses `CLLocationManager` with best accuracy and a 10-meter distance filter, but there is no order-scoped cadence or background execution policy. `WebSocketService` sends location messages and runs a 30-second heartbeat only for blind users; its minimum-send check can drop a message when timers collide. The app decodes volunteer-to-blind locations but not the reverse direction. AMap supports point annotations but not route polylines. The canonical local OpenAPI does not yet include the live backend's typed track endpoint.

The backend confirmed that all current `lat`/`lng`/`gpsLat`/`gpsLng` inputs and outputs are GCJ-02 and that existing writes came only from AMap/Tencent location paths; historical data is therefore treated as clean GCJ-02 despite the absence of a coordinate-system column or migration. iOS converts its `CLLocationManager` WGS-84 samples exactly once at the network boundary. Any future backend-native/overseas WGS-84 source must be converted at the server write boundary.

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

Outgoing messages use a small serialized queue that preserves the 500 ms minimum interval rather than silently dropping a heartbeat or location when timers coincide. Production `/ws/blind` and `/ws/volunteer` both accept `PING` and immediately return `PONG`. The server closes a connection after 90 seconds with no client message using `SESSION_NOT_RELIABLE`; iOS does not invent a missed-PONG counter and uses the existing 3/6/12/30-second reconnect path when the socket closes. `PONG` remains observable transport health only.

Each physical socket is assigned a monotonically increasing connection generation. Receive/send failures and heartbeat callbacks from an older generation cannot disconnect or reschedule the replacement socket, and one active generation can have only one pending reconnect. Volunteer reconnect recovery immediately reports the latest valid real location before refreshing dispatch summary. The app retains only privacy-safe in-memory dispatch diagnostics (role, state, generation, message type, order ID, timestamp, decode field and received/retained/presented stage); it never records tokens, coordinates, contact data, addresses or message bodies. `/api/orders/available` is not a dispatch-recovery source unless the backend later freezes it as a participant-authorized pending-offer contract.

Home refresh loading state is cancellation-safe. External navigation, scene changes, lock/background transitions, and SwiftUI task replacement may cancel an in-flight profile/order/dispatch refresh; cancellation must always release the visible loading state and must not be announced as a network failure.

`ContentView` uses one explicit `RootRoute` rather than independently derived, animated root branches. An identity-scoped hydration task loads the required profile/contact or registration facts in parallel behind a visible recovery gate, then commits exactly one root destination. Token, account, role, or generation changes cancel the prior hydration; stale results cannot mount an old page. Root transitions do not use opacity animation, and AMap exists only inside the final home route.

Home request groups separate retained content from a nonmodal refresh phase and use an anonymous request ID, owned task, and real 20-second cancellation deadline. Volunteer dispatch summary is the primary independent request and does not wait for profile, registration, location upload, or propagation delay. Existing authoritative content remains visible during refresh failure. Lifecycle, WebSocket reconnect, timer, and manual triggers for the same endpoint coalesce into one in-flight request without cancellation/restart, so repeated triggers cannot postpone its original deadline.

Debug, DemoRelease, and Production mount a live AMap directly on each committed blind-runner or volunteer home. The single `RootRoute` guarantees that only the current role's home `MAMapView` exists, and leaving or switching the role tears that map down. Home refreshes update map inputs without conditionally replacing the map root. Missing local AMap configuration and the explicit UI-test map-disable flag retain a configuration-failure fallback, but there is no product/release placeholder policy. A non-MainActor `HomeLoadCoordinator` owns the request/deadline race, while ViewModels commit only the current request result on MainActor. Until the first authoritative active-order lookup completes, blind-runner booking remains guarded to prevent duplicate orders while settings, records, speech, map inspection, and retry stay usable. A privacy-safe run-loop watchdog records only anonymous page category and stall duration.

Volunteer order transitions separate the state-changing POST from authoritative confirmation. The POST has its own 12-second application deadline; success or an uncertain transport outcome immediately releases the spinner and enters `awaitingConfirmation` while preventing only a duplicate submission of the same transition. A validated associated `ORDER_STATUS_CHANGED` event or a separate order-detail request with a 20-second hard deadline confirms the canonical status. If neither confirms, the UI enters `confirmationDelayed` with a read-only status retry and leaves maps, navigation, scrolling, cancellation entry, and back navigation usable. Explicit backend rejection restores the original action; 401 follows session expiration. The client never invents a successful status or repeats the state-changing POST during confirmation.

`AppRealtimeCoordinator` converts associated `ORDER_STATUS_CHANGED` payloads into `RealtimeOrderStatusUpdate` only when both status strings decode and the event's `fromStatus` matches the current in-memory status when known. Matching pages apply this validated event before refreshing full detail. Wrong-order, invalid, duplicate, and late events request safe REST recovery but cannot mutate local order state.

The coordinator retains at most 256 `messageId` UUID identities with their order/from/to fingerprint for the current login session. An exact replay is discarded before UI, speech, or REST refresh; a reused UUID with a different fingerprint is never applied and triggers at most one bounded safe refresh. Missing or malformed UUIDs are logged as anonymous contract anomalies but remain compatible with the existing association and status reconciler. This cache survives physical WebSocket reconnects and is cleared on logout or identity replacement.

Lifecycle speech remains client-authored. A validated structured status event announces its local accessibility copy once, while parallel lifecycle `APP_NOTIFICATION` templates are suppressed for active orders. A 30-second recently-applied target-status semantic cache also suppresses a template that arrives after a terminal update has removed the active order. Safety alerts and unrelated notifications are unaffected. REST detail refresh and five-second blind-order polling remain independent fallback/recovery paths.

An in-memory `OrderStatusReconciler` is the single status decision point for all home/detail flows. It tracks the accepted status and request generation for each active order, accepts legal forward WebSocket/REST candidates, and rejects a REST regression that began before a realtime transition. Applying a status finishes before location, escort-session, map, or detail-recovery work is scheduled for a later executor turn.

`LiveEscortSessionCoordinator.updateOwnedOrder` stores state and schedules one asynchronous reconcile. Duplicate order/status inputs coalesce, normal device location is not restarted, background location changes only on `IN_PROGRESS` boundary crossings, and one in-flight location send retains only the newest pending sample. `WebSocketService` decodes JSON away from the main actor while preserving reliable status/notification ordering; peer-location floods coalesce per order/role before the main-actor publisher.

Display-only auxiliary/background maps do not intercept vertical scroll gestures, and AMap annotations are mutated only when their semantic content changes. Anonymous performance diagnostics cover command, event, REST confirmation, escort scheduling, location readiness, WebSocket enqueue, and map update phases without JWT, account, order identifier, or coordinates; the run-loop watchdog includes only the current anonymous phase.

Network diagnostics retain only normalized endpoint category, HTTP status, duration, cancellation/transport/decoding stage, and an anonymous request ID. Numeric resource IDs are redacted and tokens, phones, names, coordinates, and response bodies are excluded. MetricKit processing records only aggregate crash/hang counts; classification of a device termination still requires the system diagnostic and is not guessed from UI symptoms.

XCTest must not share the normal app's persistence domain. `AppStatePersistence` selects the standard domain only for a normal launch, a process-isolated unit-test domain for hosted XCTest, and a dedicated reset-on-launch UI-test domain for XCUI launches. Home refreshes also carry a generation and a 20-second visible deadline: an obsolete response cannot replace a newer refresh, and a deadline releases the loading overlay and exposes retry. Real-device scripts compare only a hash of environment/role/user ID/token presence and content before/after tests, terminate test hosts, then reinstall and launch `blindRun-Demo` for manual cloud validation.

### 3. Continue location during lock/background only for an active run

The target enables the iOS `location` background mode and appropriate location usage descriptions. When an order enters `IN_PROGRESS`, `LocationService` uses fitness-oriented continuous updates, background updates, a visible system background-location indicator where applicable, and a deliberate accuracy/distance policy. It disables background updates and returns to the normal policy when the run ends.

The app explains background collection before service begins. Permission denial or later revocation produces visible/TTS guidance and a degraded recording warning; it does not synthesize points or silently use demo coordinates. Real-device validation covers locking both devices and backgrounding each role for a sustained interval.

### 4. Normalize coordinates exactly once at the network boundary

Internal location samples carry coordinate-system provenance. Raw device coordinates are converted exactly once by a centralized `BackendCoordinateNormalizer` into GCJ-02 before WebSocket upload. Incoming peer coordinates and track points are interpreted as GCJ-02 and passed directly to AMap. Distance/pace comparisons use coordinates expressed in the same system.

No feature ViewModel performs ad hoc conversion. Fixtures around known Chinese locations test conversion direction and prevent double conversion. All inbound order, REST fallback, WebSocket peer, emergency, and track coordinates are interpreted as GCJ-02. No legacy client-side identification/migration is required because the backend confirmed no historical WGS-84 write path existed.

### 5. Present peer location only to the associated order participants

During `DRIVER_EN_ROUTE`, `DRIVER_ARRIVED`, and `IN_PROGRESS`, the blind-runner map may display the associated volunteer marker and the volunteer map may display the associated blind-runner marker. Samples must match the active order, pass coordinate validation, and be no older than 15 seconds. Stale markers are hidden and explicitly marked unavailable.

Each role ViewModel owns at most one cancellable peer-expiry task. A fresh matching sample replaces the prior task; expiration rechecks both order and sample identity before clearing the marker, and page exit, order termination, or order replacement cancels it immediately. Peer freshness is not polled with a SwiftUI `TimelineView`, especially not one created from dynamic `.now`, because rebuilding an immediately eligible periodic schedule during AttributeGraph evaluation can create a self-sustaining high-CPU refresh loop.

The volunteer home also avoids a self-referential layout graph. Its top status area is not measured through a `PreferenceKey` and written back into the panel layout; the reserved top boundary is a deterministic function of the safe area and whether an active-order card is present. This remains stable even when SwiftUI reevaluates the root view continuously during map or order updates.

The AMap bridge returns a stable UIKit host view to SwiftUI and constrains `MAMapView` as its internal child, keeping the map renderer's continuous layout invalidations out of the representable root. It also hides the map's continuously mutating UIKit accessibility descendants and exposes one stable SwiftUI summary element. Rendering uses an automatically decreasing low frame-rate ceiling in the default run-loop mode so parent scroll tracking wins over idle map rendering. Location presentation is deduplicated: a stationary Core Location timestamp may refresh the latest reportable sample without publishing the entire environment tree; view invalidation is reserved for an actual coordinate, permission, or error-state change.

Root notification and escort-health announcements retain the last handled notification UUID or health enum across SwiftUI subscription reconstruction. `@Published` is a current-value publisher, so a newly reconstructed `onReceive` subscription immediately replays its value; subscription-local `removeDuplicates()` is insufficient. The gate records the identity before invoking TTS, preventing TTS's own published state from invalidating the root and recursively replaying the same event.

Visible text and accessibility labels identify the role and freshness without speaking raw latitude/longitude. Peer samples are in-memory only and are cleared when the associated session ends or identity changes.

### 6. Treat escort safety alerts as high-priority events, not order states

The backend remains authoritative for distance and signal-loss detection. Production sends all templates as flat `APP_NOTIFICATION` payloads: `{type,messageId,eventType,timestamp,body,ttsText,priority}`. `messageId`, template `eventType`, and `timestamp` are outer fields; `orderId` is not currently delivered. iOS routes `ESCORT_DISTANCE_ALERT` and `ESCORT_SIGNAL_LOST` only by `eventType`, presents the server-provided role-specific body/TTS through equivalent banner, VoiceOver, and TTS, and deduplicates by UUID. Display-copy changes do not affect classification. Because the payload lacks order identity, iOS presents a recognized alert only while exactly one owned order is `IN_PROGRESS`. If a future payload provides `orderId`, the backend guarantees it identifies the triggering current order and iOS must match it strictly. The client does not create an emergency event, cancel/finish the order, or claim that rescue has been dispatched.

### 7. Use the blind-runner track as the completed route

After `COMPLETED`, either participant may request `GET /api/orders/{id}/track`. `OrderTrackResponse` decodes guaranteed order `status`, ordered blind and volunteer raw `TrackPoint` arrays, and per-role `TrackStats`. Arrays preserve 0, 1, or multiple logged points. When one role has fewer than two points, only that role's statistics become `distanceMeters = 0`, `durationSeconds = 0`, and `avgPaceSecPerKm = null`; iOS retains but does not draw a single point. `status` distinguishes not-started, collecting, and legacy/no-track cases. The primary summary renders:

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
- [Risk] GCJ-02 is converted twice when a future source is added. → Keep client provenance/normalization centralized and require any future backend WGS-84 source to convert at its write boundary.
- [Risk] Five-second location and 30-second ping collide with the send limiter. → Serialize queued sends instead of dropping them.
- [Risk] Peer coordinates leak outside the associated order. → Key by order/user, clear on lifecycle changes, avoid logs/persistence, and test cross-account/order isolation.
- [Risk] Client anomaly results disagree with backend separation configuration. → Require a versioned threshold/backend assessment before user-facing anomaly copy.
- [Risk] Track endpoint returns partial/null statistics. → Model null/empty fields and show honest unavailable copy rather than calculating from demo data.
- [Risk] Hosted XCTest overwrites a real device's normal token/environment because the test host uses the production bundle container. → Inject isolated persistence, hash-guard the standard domain, terminate test hosts, and restore DemoRelease before manual validation.
- [Risk] Derived root routes mount login/profile/home and AMap layers during rapid identity updates. → Hydrate behind one cancellable `RootRoute`, commit atomically, and remove root opacity transitions.
- [Risk] A deadline updates visible state but leaves serialized child requests running. → Own and cancel the complete request group, reject late request IDs, and keep retry available.
- [Risk] A state POST succeeds but its response or confirmation GET stalls, leaving the volunteer action button locked while the blind runner remains on the old state. → Bound the POST independently, publish a nonmodal awaiting-confirmation state, apply validated associated WebSocket status immediately, and bound read-only REST confirmation without retrying the POST.
- [Risk] Recreating or simultaneously mounting multiple home `MAMapView` instances can block the main run loop before timeout UI can recover. → Commit one atomic root route, keep each home map in a stable view position, unmount it on route exit, retain anonymous run-loop diagnostics, and require sustained dual-device evidence.
- [Risk] A dynamic periodic SwiftUI timeline, a child-layout Preference written back into its own parent layout, an AMap renderer rooted directly in `UIViewRepresentable`, or a current-value publisher replaying TTS after every root subscription rebuild can saturate AttributeGraph. → Replace peer polling with one ViewModel-owned cancellable expiry task, remove the self-referential volunteer-home measurement, contain and rate-limit AMap rendering inside a stable UIKit host, deduplicate location/health publications, gate announcements across subscription lifetimes, and require sustained real-map arrival validation.

## Migration Plan

1. Freeze and document GCJ-02, heartbeat, location envelopes, separation identity, track schemas, and anomaly policy.
2. Update canonical docs/OpenAPI/WebSocket contract and privacy/release risks.
3. Add typed coordinate provenance, serialized send queue, heartbeat health, and service-session coordinator behind disabled UI.
4. Add five-second foreground reporting, then `IN_PROGRESS` background capture and deterministic cleanup.
5. Add reverse peer-location decoding/presentation and separation alerts.
6. Add track models, Mock responses, AMap polylines, and accessible completed summary.
7. Restore one stable live AMap on each committed role home while preserving missing-key/test fallback.
8. Validate on Mock, focused tests, cloud probes, and locked/backgrounded dual devices.

Rollback disables live-session/background reporting and peer/track presentation while preserving existing dispatch location reporting and canonical order flows.

## Open Questions

- `需要人工确认`: will the backend expose a versioned completed-track anomaly result, or will product formally approve a comparison policy? The current 100-metre/two-consecutive-breach runtime alert setting is explicitly not that approval.
