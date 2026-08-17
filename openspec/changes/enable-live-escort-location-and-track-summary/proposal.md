## Why

The cloud backend now forwards blind-runner and volunteer locations in both directions during active service and exposes `GET /api/orders/{id}/track` with both recorded tracks and per-role statistics. The iOS app currently reports volunteer location only at selected dispatch actions, does not continuously report blind-runner location, does not decode `BLIND_LOCATION_UPDATE`, and has no completed-run route or summary experience. Lock-screen/background continuity is required so a run is not fragmented when the phone is no longer foregrounded.

## What Changes

- Add a role-aware live escort session that sends `PING` every 30 seconds and each participant's `LOCATION_UPDATE` every 5 seconds over the active role WebSocket.
- Continue location capture and reporting while the app is locked or backgrounded during `IN_PROGRESS`, with explicit iOS background-location configuration, user disclosure, lifecycle cleanup, and real-device validation.
- Normalize outbound device locations exactly once to the backend's GCJ-02 wire contract and treat inbound live/track coordinates as GCJ-02 for AMap rendering.
- Receive and present `VOLUNTEER_LOCATION_UPDATE` and `BLIND_LOCATION_UPDATE` for the associated order during `DRIVER_EN_ROUTE`, `DRIVER_ARRIVED`, and `IN_PROGRESS`.
- Present backend `ESCORT_DISTANCE_ALERT` and `ESCORT_SIGNAL_LOST` notifications as high-priority visible, VoiceOver, and TTS warnings without changing order status or synthesizing an iOS SOS action.
- Add `GET /api/orders/{id}/track` models and a completed-run summary: blind-runner track is the primary "本次路线" and primary distance/duration/pace; volunteer track is decoded and retained only for approved anomaly comparison.
- Add AMap route-polyline rendering, textual/statistical accessibility equivalents, Mock behavior, focused tests, and dual-device cloud validation.

## Capabilities

### New Capabilities

- `live-escort-location-and-track-summary`: Defines service-session heartbeat/location cadence, background continuity, GCJ-02 handling, peer-location presentation, separation alerts, completed route replay, and summary hierarchy.

### Modified Capabilities

- `global-realtime-notification-handling`: Adds cadence-resume and bidirectional peer-location consumers on top of the app-lifetime coordinator.
- `formal-dispatch-service-flow`: Adds live peer positions during eligible service states and a completed-run summary without changing canonical order transitions.
- `backend-api-contract`: Adds GCJ-02 semantics, both WebSocket location directions, heartbeat behavior, separation-alert identity, and the typed track endpoint.

## Impact

- iOS location/runtime: `LocationService`, background modes and privacy strings, a new escort-session coordinator, serialized WebSocket sends, lifecycle handling, and battery use.
- iOS UI/data: WebSocket models, blind/volunteer service ViewModels, AMap peer markers/polyline overlays, order completion screens, track models, Mock API, TTS, and VoiceOver.
- Backend contract: every current upload/response coordinate is GCJ-02 and existing writes came only from AMap/Tencent location paths, both role sockets support `PING`/`PONG`, every flat `APP_NOTIFICATION` carries outer UUID `messageId` and template `eventType`, and track responses always include order `status` outside 403/404. Track arrays retain 0/1/multiple raw points while per-role stats become 0/0/null below two points. The current 100-metre/two-breach engineering threshold is not an approved completed-track anomaly policy.
- Privacy: location is sent only for authenticated service/dispatch purposes, background capture is clearly disclosed, raw coordinates are not shown as normal text or logged, and capture stops when no longer eligible.
- Sequencing: requires `complete-realtime-fallback-and-notifications`; the revised in-run SOS change then reuses its latest GCJ-02 service location.
