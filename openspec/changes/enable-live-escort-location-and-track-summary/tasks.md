## 1. Contract And Documentation

- [ ] 1.1 Freeze the GCJ-02 contract for device upload, order coordinates, REST fallback, both WebSocket directions, track points, and legacy stored data; record unresolved behavior as `需要人工确认`.
- [ ] 1.2 Confirm volunteer `PING/PONG`, production separation-alert envelope/identity, track error/no-data behavior, and a versioned volunteer-track anomaly assessment or product-approved comparison threshold.
- [ ] 1.3 Update `AGENTS.md`, `plan.md`, product/scope/story/flow/page/data/architecture/accessibility/task docs with approved live peer location, background collection, completed summary, privacy, battery, and release risks.
- [ ] 1.4 Update `docs/07-api-contract.openapi.yaml` and `docs/websocket-protocol.md` with GCJ-02 semantics, 30-second heartbeat, five-second location cadence, both location directions, separation alerts, and typed track schemas.

## 2. Coordinate And Transport Foundation

- [ ] 2.1 Add coordinate-system provenance and one centralized device-to-GCJ-02 network normalizer with known-location and double-conversion tests.
- [ ] 2.2 Treat inbound peer/order/track coordinates according to the frozen GCJ-02 contract and remove feature-level ad hoc conversion.
- [ ] 2.3 Replace drop-on-collision sends with a serialized queue that preserves the 500 ms minimum interval.
- [ ] 2.4 Enable 30-second `PING`/`PONG` health for both roles, documented missing-PONG reconnect behavior, and immediate resume after reconnect.

## 3. Live Escort Session And Background Location

- [ ] 3.1 Implement `LiveEscortSessionCoordinator` on top of `AppRealtimeCoordinator`, keyed to the owned active order and role.
- [ ] 3.2 Send an immediate location on eligible session start/reconnect and the latest valid GCJ-02 location every five seconds through `DRIVER_EN_ROUTE`, `DRIVER_ARRIVED`, and `IN_PROGRESS`.
- [ ] 3.3 Add iOS background-location mode, usage descriptions, fitness/location-manager policy, and user disclosure for mandatory lock/background continuity during `IN_PROGRESS`.
- [ ] 3.4 Stop enhanced/background capture and clear peer/session data on completion, cancellation, rematching, no-volunteer, logout, identity/token change, or loss of order association.
- [ ] 3.5 Add visible/TTS permission, stale-location, network-gap, and background-recording states; never substitute demo coordinates in cloud sessions.

## 4. Bidirectional Peer Location And Separation Alerts

- [ ] 4.1 Add `BLIND_LOCATION_UPDATE` models/decoding and route both peer directions by order and role.
- [ ] 4.2 Show fresh associated volunteer location to the blind runner and fresh associated blind-runner location to the volunteer during documented eligible states.
- [ ] 4.3 Hide/mark stale peer markers, clear them at session/account boundaries, and keep raw coordinates out of visible text, accessibility output, persistence, and logs.
- [ ] 4.4 Decode and present `ESCORT_DISTANCE_ALERT` as a deduplicated high-priority visible/VoiceOver/TTS warning without changing `RunOrderStatus` or synthesizing SOS.

## 5. Track Models And Completed Summary

- [ ] 5.1 Add `OrderTrackResponse`, `TrackPoint`, and nullable/partial `TrackStats` models plus `GET /api/orders/{id}/track` client and Mock behavior.
- [ ] 5.2 Add stable AMap polyline overlays, primary-route viewport fitting, and empty/partial track handling.
- [ ] 5.3 Present the blind track as "本次路线" with blind distance, duration, and average pace as the primary completed summary for both roles.
- [ ] 5.4 Decode and retain the volunteer track only for the approved anomaly comparison; do not display it as the default route or emit abnormality copy before the threshold/result contract is approved.
- [ ] 5.5 Add equivalent textual, VoiceOver, TTS, and "重复当前状态" summaries independent of map inspection.

## 6. Tests And Validation

- [ ] 6.1 Add unit tests for cadence, immediate reconnect send, serialization, heartbeat health, GCJ-02 normalization, lifecycle stop conditions, and cross-order/account isolation.
- [ ] 6.2 Add background/lifecycle tests for lock, foreground/background transitions, permission revocation, location gaps, reconnect, and cleanup.
- [ ] 6.3 Add WebSocket tests for both peer directions, stale/wrong-order rejection, separation-alert deduplication, and no order-state mutation.
- [ ] 6.4 Add track decoding, null/empty/legacy data, primary-route hierarchy, formatting, AMap overlay, anomaly-policy, UI, and accessibility tests.
- [ ] 6.5 Run `node scripts/validate-docs.mjs` and `openspec validate enable-live-escort-location-and-track-summary --strict --no-interactive`.
- [ ] 6.6 Run cloud probes and sustained lock/background dual-device validation on `111` and `iPad Pro (2)`, then run the production-readiness scripts before release enablement.
