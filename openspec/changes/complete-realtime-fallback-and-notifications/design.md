## Context

`WebSocketService` already owns connection/reconnect mechanics and decodes the documented incoming message types, but screen ViewModels subscribe directly. The blind order screen consumes status, notification, and volunteer-location events only while mounted; the volunteer home consumes only `NEW_ORDER`. This can drop proximity messages, stale active-order state after navigation, and safety follow-ups. The existing OpenSpec also requires a REST volunteer-location fallback, while the higher-priority product scope says the app does not display another person's real-time position.

This design resolves the conflict as distance-only processing: the app may transiently consume the volunteer coordinate to calculate approximate distance to the fixed order start point, but it never displays the coordinate or the volunteer's live map position.

## Goals / Non-Goals

**Goals:**

- Establish one app-lifetime owner for WebSocket event routing and foreground notification state.
- Preserve feature-specific ViewModels while preventing screen-lifecycle event loss and duplicate speech.
- Add privacy-preserving REST fallback for blind-runner distance-to-start copy.
- Make priority, freshness, reconnect, and deduplication behavior testable.

**Non-Goals:**

- Notification history/inbox, APNs/background delivery, remote-notification permissions, real-time track sharing, another-party marker/direction, in-app route planning, or virtual-number calling.
- Backend proximity calculations, Redis storage, notification-template management, or scheduler implementation.

## Decisions

### 1. Add one app-lifetime realtime event coordinator

An `AppRealtimeCoordinator` owned by `AppState` will attach to the current `WebSocketService`, detach when the service changes, and translate incoming events into narrow published state/signals: foreground notification queue, order-refresh requests, latest private distance input, dispatch prompt delivery, and safety-event delivery. Feature ViewModels may observe these typed outputs instead of independently subscribing to the raw event publisher.

Alternative considered: add more cases to every screen subscription. Events would still be lost when the screen is absent and duplicate subscriptions would remain difficult to reason about.

### 2. Keep feature truth in REST-backed ViewModels

`ORDER_STATUS_CHANGED` does not directly mutate an order from the WebSocket payload. The coordinator emits a deduplicated refresh request keyed by order ID; the active feature ViewModel fetches `GET /api/orders/{id}`. This preserves the backend order detail as source of truth and avoids partial payload drift.

`NEW_ORDER` remains a volunteer dispatch prompt with its existing timeout behavior, but is delivered through the coordinator so navigation does not drop it.

Alternative considered: store every active order in the coordinator. This duplicates existing ViewModel ownership and broadens AppState into a business-data cache.

### 3. Apply priority-aware foreground presentation without a persistent inbox

The coordinator maintains a small in-memory foreground queue. `HIGH` notifications preempt normal banners and produce an immediate VoiceOver/TTS announcement unless they duplicate a local lifecycle announcement. `NORMAL` notifications are queued and presented without interrupting an active higher-priority message. Identical event keys or normalized message/type combinations within a short deduplication window are suppressed.

Lifecycle `APP_NOTIFICATION` text is not spoken when an `ORDER_STATUS_CHANGED` refresh will produce authoritative local lifecycle copy. Proximity and non-lifecycle template messages remain eligible.

Alternative considered: speak every `ttsText`. This reproduces current duplicate/noisy behavior and can announce stale template wording.

### 4. Use a privacy-preserving volunteer-distance source state machine

For `PENDING_ACCEPT`, fresh `VOLUNTEER_LOCATION_UPDATE` may be used to compute distance to `order.startLatitude/startLongitude`. For `DRIVER_EN_ROUTE` and `DRIVER_ARRIVED`, the client uses WebSocket data while it is fresh; when the socket is disconnected or no update has been received within the documented freshness window, it requests `GET /api/blind/volunteer-location` as a fallback.

The raw coordinate remains private transient ViewModel/coordinator state. The UI receives only an approximate formatted distance and freshness state. It never renders the volunteer marker, coordinate, direction, route, track, or “距您” wording. If either coordinate is missing or the fallback is stale/unavailable, distance is hidden and the user hears that the volunteer position is temporarily unavailable.

The initial freshness threshold will align with the backend location TTL documented as 30 seconds. `updatedAt` from REST is authoritative. `需要人工确认`: confirm whether the fallback endpoint returns no data or a stable error outside eligible states and confirm the timestamp format/timezone.

### 5. Preserve transport limits and reconnect responsibilities

`WebSocketService` retains 500ms minimum send spacing, heartbeat, exponential backoff, and message decoding. The coordinator observes connection replacement and connection state so it can request feature refresh/fallback after reconnect. The server remains responsible for the 64KB hard message limit; the client sends only small typed location and ping messages.

## Risks / Trade-offs

- [Risk] A global coordinator can become a new god object. → Publish narrow typed signals and keep API calls/business state in feature ViewModels.
- [Risk] Deduplication suppresses a meaningful repeated safety notification. → Use event IDs for safety events and apply text-window deduplication only to non-safety templates.
- [Risk] REST fallback increases traffic during disconnection. → Restrict it to eligible active states and the existing five-second order polling cadence.
- [Risk] Raw coordinates leak through debug output. → Make coordinate state private, prohibit logging, and test the rendered/accessibility tree for absence of coordinates and markers.
- [Risk] Two changes modify realtime safety routing. → Implement this coordinator before `enable-independent-sos-safely`, then let the safety change add domain-specific SOS handling.

## Migration Plan

1. Update docs and the typed OpenAPI/WebSocket fallback and notification contracts.
2. Add coordinator and notification/freshness models behind existing `WebSocketService`.
3. Move blind and volunteer subscribers one feature at a time, removing raw subscriptions after parity tests.
4. Add REST distance fallback and privacy-preserving presentation.
5. Add priority banner/TTS handling and deduplication.
6. Run focused reconnect/navigation/privacy tests followed by dual-device cloud validation.

Rollback can return subscribers to feature ViewModels and disable REST fallback without data migration. The docs must not revert to promising another-party real-time position.

## Open Questions

- `需要人工确认`: What exact REST `updatedAt` format/timezone and no-data response are returned outside `DRIVER_EN_ROUTE` and `DRIVER_ARRIVED`?
- `需要人工确认`: Are priority values limited to `HIGH` and `NORMAL`, and is there a stable notification/event identifier suitable for deduplication?
