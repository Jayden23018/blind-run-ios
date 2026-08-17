## 1. Contract And Documentation

- [x] 1.1 Confirm fallback timestamp/no-data semantics, notification envelope/identity/priority, `BLIND_LOCATION_UPDATE`, and separation-alert payloads; record unresolved backend behavior as `需要人工确认`.
- [x] 1.2 Update product, flow, page, data, architecture, accessibility, and WebSocket docs with app-lifetime event ownership and dependency boundaries.
- [x] 1.3 Update `docs/07-api-contract.openapi.yaml` and `docs/websocket-protocol.md` with typed coordinator inputs and fallback response schemas.

## 2. Realtime Coordination Foundation

- [x] 2.1 Add narrow connection, notification, order-refresh, dispatch, peer-location, separation-alert, and safety-event output models.
- [x] 2.2 Implement one `AppRealtimeCoordinator` owned by `AppState`, with exactly-one attachment and cleanup on logout, role/token change, or service replacement.
- [x] 2.3 Route `ORDER_STATUS_CHANGED` into coalesced REST refresh requests while keeping full order state in feature ViewModels.
- [x] 2.4 Route `NEW_ORDER` through the coordinator without changing timeout/respond behavior or losing the prompt during navigation.
- [x] 2.5 Decode and route `VOLUNTEER_LOCATION_UPDATE` and `BLIND_LOCATION_UPDATE` by order and role without logging raw coordinates or adding peer UI.
- [x] 2.6 Route separation and emergency messages by stable event identity without implementing their feature actions in this change.

## 3. Foreground Notification Handling

- [x] 3.1 Implement an in-memory priority queue where `HIGH` preempts `NORMAL` and visible, VoiceOver, and TTS presentation stay equivalent.
- [x] 3.2 Implement lifecycle-template suppression and bounded non-safety deduplication while preserving distinct safety event IDs.
- [x] 3.3 Add shared foreground presentation UI and migrate blind/volunteer raw subscriptions without duplicate handling.

## 4. Fallback And Transport Recovery

- [x] 4.1 Type the existing blind-runner volunteer-location REST fallback and preserve its current eligible pre-service behavior.
- [x] 4.2 Preserve 500 ms serialized sends, reconnect backoff, unknown-message tolerance, and five-second order polling.
- [x] 4.3 On reconnect, request relevant order/summary refresh and notify dependent feature coordinators to resume their own cadence.

## 5. Tests And Validation

- [x] 5.1 Add unit tests for attach/detach, service replacement, event routing, refresh coalescing, dispatch retention, priority, and deduplication.
- [x] 5.2 Add tests for both peer-location directions, invalid/wrong-order sample rejection, separation/safety event identity, and absence of coordinate logs.
- [x] 5.3 Add UI/accessibility tests for foreground priority, lifecycle speech exactly once, and navigation-independent delivery.
- [x] 5.4 Run `node scripts/validate-docs.mjs` and `openspec validate complete-realtime-fallback-and-notifications --strict --no-interactive`.
- [x] 5.5 Run focused unit/UI tests plus required real-device validation on `111` and `iPad Pro (2)` before applying dependent changes.
