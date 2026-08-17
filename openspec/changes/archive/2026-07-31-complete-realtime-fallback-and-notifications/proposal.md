## Why

`WebSocketService` already connects, reconnects, and decodes several backend messages, but individual screens still own subscriptions. Events can therefore be dropped during navigation, duplicated by multiple screens, or handled differently by the blind-runner and volunteer flows. The upcoming live escort, track-summary, and in-run SOS changes all need one app-lifetime routing foundation before they can safely add feature behavior.

## What Changes

- Add one `AppRealtimeCoordinator`, owned by `AppState`, that attaches exactly once to the active role WebSocket and survives screen navigation.
- Route order refresh, dispatch prompt, foreground notification, peer-location, separation-alert, and emergency-event signals into narrow feature-facing outputs.
- Keep authoritative order state in REST-backed ViewModels; WebSocket status messages request refreshes rather than constructing partial orders.
- Apply priority-aware foreground presentation, VoiceOver/TTS equivalence, lifecycle-message suppression, and safety-aware deduplication.
- Preserve the 500 ms transport send limit, exponential reconnect policy, unknown-message tolerance, five-second order polling fallback, and typed REST volunteer-location fallback.
- Make the coordinator transport- and feature-neutral: the later `enable-live-escort-location-and-track-summary` change owns five-second service-session location reporting and peer-marker/track presentation, while `enable-independent-sos-safely` owns in-run SOS state.

## Capabilities

### New Capabilities

- `global-realtime-notification-handling`: Defines app-lifetime WebSocket ownership, typed routing, priority presentation, deduplication, authoritative refresh signaling, and reconnect continuity.

### Modified Capabilities

- `system-dispatch-flow`: Keeps pre-service volunteer-location fallback and routes dispatch/status events through the global coordinator.
- `formal-dispatch-service-flow`: Keeps order screens status-driven and establishes feature-neutral peer-location routing for later service-session behavior.
- `backend-api-contract`: Types fallback, notification, peer-location, alert, priority, timestamp, and event identity fields needed by the coordinator.

## Impact

- iOS architecture: `AppState`, `WebSocketService`, incoming event models, blind/volunteer ViewModels, and shared foreground notification presentation.
- External contracts: `/ws/blind`, `/ws/volunteer`, `APP_NOTIFICATION`, `ORDER_STATUS_CHANGED`, `NEW_ORDER`, `VOLUNTEER_LOCATION_UPDATE`, `BLIND_LOCATION_UPDATE`, separation alerts, emergency messages, and `GET /api/blind/volunteer-location`.
- Sequencing: this foundation must be implemented before `enable-live-escort-location-and-track-summary` and the revised `enable-independent-sos-safely` change.
- Tests: coordinator lifecycle, routing, refresh coalescing, notification priority/deduplication, reconnect behavior, and dual-device cloud validation.
