## 1. Contract And Documentation

- [ ] 1.1 Obtain human confirmation for fallback `updatedAt`/timezone/no-data semantics, priority enum, and stable notification identifiers before implementing affected parsing.
- [ ] 1.2 Update product/scope/story/flow/page/data/architecture/accessibility/WebSocket docs to define distance-to-start-only behavior and remove every promise to display another party's real-time position.
- [ ] 1.3 Update `docs/07-api-contract.openapi.yaml` and `docs/websocket-protocol.md` with typed fallback data/freshness and notification priority/identity semantics.

## 2. Realtime Coordination Foundation

- [ ] 2.1 Add narrow foreground-notification, order-refresh, dispatch-delivery, private distance-source, and safety-event models with no raw-payload UI exposure.
- [ ] 2.2 Implement one `AppRealtimeCoordinator` owned by AppState that attaches once to the active WebSocket service and cleanly detaches on logout, role switch, or service replacement.
- [ ] 2.3 Route `ORDER_STATUS_CHANGED` into deduplicated REST refresh signals and keep canonical order state in feature ViewModels.
- [ ] 2.4 Route `NEW_ORDER` through the coordinator without changing its timeout/respond contract or losing prompts during navigation.

## 3. Foreground Notification Handling

- [ ] 3.1 Implement an in-memory priority queue where `HIGH` preempts `NORMAL` and visible, VoiceOver, and TTS presentation stay equivalent.
- [ ] 3.2 Implement lifecycle-template suppression and bounded non-safety deduplication while preserving distinct safety event IDs.
- [ ] 3.3 Add shared foreground banner/presentation UI and migrate blind/volunteer feature subscribers from raw WebSocket events without duplicate handling.
- [ ] 3.4 Ensure volunteer proximity and status notifications are handled from home and service flows rather than ignored.

## 4. Privacy-Preserving Distance Fallback

- [ ] 4.1 Add a freshness state machine using fresh WebSocket location for eligible states and the typed REST fallback only for `DRIVER_EN_ROUTE`/`DRIVER_ARRIVED` when disconnected or stale.
- [ ] 4.2 Integrate fallback polling with the existing five-second order cadence and stop it outside eligible active states or after fresh WebSocket recovery.
- [ ] 4.3 Expose only approximate distance to the fixed order start point and freshness/unavailable copy; prohibit coordinate text, another-party markers, direction, route, track, and “距您”.
- [ ] 4.4 Ensure raw volunteer coordinates remain private transient state and are absent from logs, screenshots, accessibility trees, and user-facing diagnostics.

## 5. Transport Recovery

- [ ] 5.1 Preserve 500ms send spacing, heartbeat, exponential backoff, unknown-message tolerance, and location-report timing while adding coordinator connection-state observation.
- [ ] 5.2 Trigger relevant active-order/summary refresh and location fallback decisions after disconnect/reconnect without duplicate subscriptions.

## 6. Tests And Validation

- [ ] 6.1 Add unit tests for coordinator attach/detach, event routing, refresh coalescing, priority queueing, deduplication, and distinct safety event IDs.
- [ ] 6.2 Add tests for WebSocket freshness, 30-second stale transition, REST fallback/no-data/recovery, distance formatting, and absence of raw coordinates or live markers.
- [ ] 6.3 Add UI/accessibility tests for notification priority, lifecycle speech exactly once, navigation event retention, volunteer proximity, and privacy wording.
- [ ] 6.4 Run `node scripts/validate-docs.mjs` and `openspec validate complete-realtime-fallback-and-notifications --strict --no-interactive`.
- [ ] 6.5 Run focused unit/UI tests, cloud WebSocket/fallback probes, and required dual-device validation on `111` and `iPad Pro (2)` before applying the SOS safety change.
