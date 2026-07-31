## Context

The current app has a role-scoped `WebSocketService`, but feature screens subscribe directly to its publisher. The blind order screen handles status, notification, volunteer location, and some emergency messages only while mounted; volunteer home and service screens handle different subsets. Upcoming continuous bidirectional location, track summaries, separation alerts, and dual-role SOS would multiply those subscriptions and increase loss and duplication risk.

This change provides the app-lifetime routing layer only. Feature policy—when a peer marker is visible, when five-second location capture runs, how completed tracks are summarized, and when SOS is available—belongs to the dependent changes.

## Goals / Non-Goals

**Goals:**

- Establish one app-lifetime owner for decoded WebSocket event routing.
- Keep feature truth in REST-backed ViewModels while coalescing refresh signals.
- Deliver dispatch, peer-location, alert, notification, and safety signals across navigation.
- Make priority, reconnect, deduplication, and subscription replacement testable.

**Non-Goals:**

- Implementing five-second GPS capture, background location, peer map markers, track replay, run statistics, separation policy, or SOS UI.
- Adding APNs/background push, a persistent notification inbox, in-app route planning, backend schedulers, or backend source code.

## Decisions

### 1. Add one app-lifetime realtime coordinator

`AppRealtimeCoordinator`, owned by `AppState`, attaches to the current `WebSocketService`, detaches when token/role/service changes, and publishes narrow typed outputs: order refresh requests, dispatch delivery, foreground notifications, peer-location samples keyed by order/role, separation alerts, safety events, and connection transitions.

Feature ViewModels subscribe to coordinator outputs rather than the raw socket publisher. The coordinator does not become the owner of full orders, maps, run summaries, or SOS business state.

### 2. Preserve REST as authoritative order truth

`ORDER_STATUS_CHANGED` emits a coalesced refresh request keyed by order ID. Feature ViewModels fetch `GET /api/orders/{id}` and generate local lifecycle copy from the canonical response. `NEW_ORDER` remains a timed backend dispatch prompt but is retained across navigation until handled or expired.

### 3. Route peer location without deciding feature presentation

The coordinator decodes and routes both `VOLUNTEER_LOCATION_UPDATE` and `BLIND_LOCATION_UPDATE` as typed, order-scoped samples. It rejects invalid coordinates, ignores samples for another active order, never logs raw coordinates, and exposes no raw payload strings.

Before `enable-live-escort-location-and-track-summary` is applied, existing pre-service blind-runner distance behavior remains unchanged. The dependent change defines service-session peer markers, five-second reporting, background capture, and completed track behavior.

### 4. Apply priority-aware foreground presentation

`HIGH` notifications preempt `NORMAL` messages. Equivalent lifecycle templates are suppressed when an order refresh will produce authoritative local copy. Non-safety duplicates are bounded by stable event ID when present or normalized type/text/time fallback; distinct safety event IDs are never collapsed.

### 5. Preserve transport responsibilities

`WebSocketService` remains responsible for connection URL construction, serialized sends, the 500 ms minimum interval, reconnect backoff, receive loop, and unknown-message tolerance. The coordinator observes connection state and requests feature refresh/resume work after reconnect. Cadence policy such as 30-second `PING` and five-second service location belongs to the live-escort change because the backend is still finalizing its GCJ-02 contract.

### 6. Keep the existing REST fallback narrow

`GET /api/blind/volunteer-location` remains a pre-service fallback for eligible blind-runner states when WebSocket location is missing or stale. Its typed timestamp/no-data contract must be confirmed before parsing is finalized. It is not a replacement for the bidirectional `IN_PROGRESS` stream or completed track endpoint.

## Risks / Trade-offs

- [Risk] The coordinator becomes a god object. → Publish narrow outputs and keep feature API calls/state in feature coordinators or ViewModels.
- [Risk] Multiple subscribers still process the same event. → Migrate each raw subscription and assert exactly-one attachment in tests.
- [Risk] Notification deduplication suppresses safety information. → Key safety messages by event ID and never text-deduplicate distinct safety events.
- [Risk] Peer coordinates leak into diagnostics. → Validate ranges, keep typed samples in memory, prohibit coordinate logging, and test logs/accessibility output.
- [Risk] Dependent changes assume transport behavior not yet confirmed by the backend. → Keep cadence and GCJ-02 normalization out of this foundation and gate them in the live-escort contract.

## Migration Plan

1. Update canonical WebSocket/OpenAPI documentation for typed coordinator inputs.
2. Add coordinator output models and exactly-one attachment lifecycle.
3. Move order refresh and dispatch delivery from screen subscriptions.
4. Move foreground notification and safety-event routing.
5. Route both peer-location message types without changing current UI behavior.
6. Run focused lifecycle/reconnect tests and dual-device cloud validation.
7. Apply `enable-live-escort-location-and-track-summary`, then the revised in-run SOS change.

Rollback restores feature subscriptions one feature at a time. It does not change backend state or stored data.

## Open Questions

- `需要人工确认`: exact `GET /api/blind/volunteer-location` timestamp timezone and no-data response.
- `需要人工确认`: canonical notification envelope (`APP_NOTIFICATION` flat fields versus `NOTIFICATION` with nested `data`), stable event identifier, and priority enum.
- `需要人工确认`: canonical `BLIND_LOCATION_UPDATE` and separation-alert envelope used by the production WebSocket service.
