## Why

The WebSocket layer parses real-time messages, but delivery is owned by individual screens, so notifications can be dropped outside those screens and blind-runner volunteer-distance data has no REST fallback. The frontend must reliably surface relevant events while honoring the decision not to display another person's real-time position.

## What Changes

- Add an app-level WebSocket event coordinator that survives navigation and routes order, notification, dispatch, and safety events to the correct feature state.
- Use `GET /api/blind/volunteer-location` only as a fallback source for calculating distance to the order start point when `/ws/blind` is unavailable or location updates are stale.
- Do not display the other party's live coordinate, map marker, movement direction, route, or track; expose only an approximate distance to the fixed order start point and freshness copy.
- Apply priority-aware foreground presentation for `HIGH` and `NORMAL` `APP_NOTIFICATION` messages with VoiceOver/TTS behavior and lifecycle-message deduplication.
- Ensure volunteer proximity and order-status notifications are not ignored on the volunteer home or service flow.
- Keep the existing 500ms client send interval, reconnect policy, 5-second order-detail polling, real phone-number behavior, and no virtual-number integration.
- Do not add notification history, APNs/background push, in-app route planning, or live track sharing without a later contract.

## Capabilities

### New Capabilities

- `global-realtime-notification-handling`: Defines app-level real-time event ownership, priority presentation, TTS/VoiceOver behavior, deduplication, and fallback freshness rules.

### Modified Capabilities

- `system-dispatch-flow`: Replaces ambiguous live-location display language with distance-to-start-only presentation and mandatory REST fallback when WebSocket location is unavailable.
- `formal-dispatch-service-flow`: Adds REST distance fallback and explicitly forbids exposing the other party's live coordinates or real-time position.
- `backend-api-contract`: Types the volunteer-location fallback response and the priority/timestamp fields required for deterministic foreground notification handling.

## Impact

- iOS architecture: `AppState`, `WebSocketService`, incoming event models, blind order status, volunteer home/service ViewModels, and shared notification presentation.
- External contracts: `/ws/blind`, `/ws/volunteer`, `APP_NOTIFICATION`, `ORDER_STATUS_CHANGED`, `VOLUNTEER_LOCATION_UPDATE`, and `GET /api/blind/volunteer-location`.
- Documentation: resolve the conflict between location fallback requirements and the higher-priority product statement that the app does not display the other party's real-time position.
- Tests: event delivery across navigation, priority handling, duplicate speech suppression, stale/fallback transitions, distance-only privacy, reconnect behavior, and dual-device cloud validation.
