> **归档前必读（2026-07-31 记）**：`openspec 1.7.0` 的 `archive` 有个 guard —— `## MODIFIED Requirements`
> 下的每条 requirement 必须**完整重写**，缺任何一个主 spec 里已有的 scenario 就直接中止。本 change 的
> `specs/formal-dispatch-service-flow/spec.md` 对 `Blind runner state updates remain status driven`
> 只写了 2 个 scenario，而主 spec `openspec/specs/formal-dispatch-service-flow/spec.md` 现在有 4 个
> （2026-07-31 归档 `complete-realtime-fallback-and-notifications` 时又补进去一些）。
> **归档前先把 delta 补全到与主 spec 一致，否则要么归档失败，要么把主 spec 的细则冲掉。**
> 同一个坑在归档 realtime 那个 change 时已经踩过三次。

## 1. Contract And Documentation

- [x] 1.1 Freeze the GCJ-02 contract for device upload, order coordinates, REST fallback, both WebSocket directions, track points, and backend-confirmed clean legacy stored data.
- [x] 1.2 Confirm volunteer `PING/PONG`, flat production `APP_NOTIFICATION` outer `messageId`/`eventType`, raw track point/status behavior, and record the unapproved volunteer-track anomaly threshold as `需要人工确认`.
- [x] 1.3 Update `AGENTS.md`, `plan.md`, product/scope/story/flow/page/data/architecture/accessibility/task docs with approved live peer location, background collection, completed summary, privacy, battery, and release risks.
- [x] 1.4 Update `docs/07-api-contract.openapi.yaml` and `docs/websocket-protocol.md` with GCJ-02 semantics, 30-second heartbeat, five-second location cadence, both location directions, escort alerts, and typed track schemas.

## 2. Coordinate And Transport Foundation

- [x] 2.1 Add coordinate-system provenance and one centralized device-to-GCJ-02 network normalizer with known-location and double-conversion tests.
- [x] 2.2 Treat inbound peer/order/track coordinates according to the frozen GCJ-02 contract and remove feature-level ad hoc conversion.
- [x] 2.3 Replace drop-on-collision sends with a serialized queue that preserves the 500 ms minimum interval.
- [x] 2.4 Enable 30-second `PING`/`PONG` health for both roles, documented missing-PONG reconnect behavior, and immediate resume after reconnect.
- [x] 2.5 Isolate each physical WebSocket by connection generation, deduplicate reconnect scheduling, add privacy-safe dispatch delivery diagnostics, and immediately restore volunteer location/readiness after reconnect.

## 3. Live Escort Session And Background Location

- [x] 3.1 Implement `LiveEscortSessionCoordinator` on top of `AppRealtimeCoordinator`, keyed to the owned active order and role.
- [x] 3.2 Send an immediate location on eligible session start/reconnect and the latest valid GCJ-02 location every five seconds through `DRIVER_EN_ROUTE`, `DRIVER_ARRIVED`, and `IN_PROGRESS`.
- [x] 3.3 Add iOS background-location mode, usage descriptions, fitness/location-manager policy, and user disclosure for mandatory lock/background continuity during `IN_PROGRESS`.
- [x] 3.4 Stop enhanced/background capture and clear peer/session data on completion, cancellation, rematching, no-volunteer, logout, identity/token change, or loss of order association.
- [x] 3.5 Add visible/TTS permission, stale-location, network-gap, and background-recording states; never substitute demo coordinates in cloud sessions.

## 4. Bidirectional Peer Location And Separation Alerts

- [x] 4.1 Add `BLIND_LOCATION_UPDATE` models/decoding and route both peer directions by order and role.
- [x] 4.2 Show fresh associated volunteer location to the blind runner and fresh associated blind-runner location to the volunteer during documented eligible states.
- [x] 4.3 Hide/mark stale peer markers, clear them at session/account boundaries, and keep raw coordinates out of visible text, accessibility output, persistence, and logs.
- [x] 4.4 Decode and present `ESCORT_DISTANCE_ALERT` as a deduplicated high-priority visible/VoiceOver/TTS warning without changing `RunOrderStatus` or synthesizing SOS.

## 5. Track Models And Completed Summary

- [x] 5.1 Add `OrderTrackResponse`, `TrackPoint`, and nullable/partial `TrackStats` models plus `GET /api/orders/{id}/track` client and Mock behavior.
- [x] 5.2 Add stable AMap polyline overlays, primary-route viewport fitting, and empty/partial track handling.
- [x] 5.3 Present the blind track as "本次路线" with blind distance, duration, and average pace as the primary completed summary for both roles.
- [x] 5.4 Decode and retain the volunteer track only for the approved anomaly comparison; do not display it as the default route or emit abnormality copy before the threshold/result contract is approved.
- [x] 5.5 Add equivalent textual, VoiceOver, TTS, and "重复当前状态" summaries independent of map inspection.

## 6. Tests And Validation

- [x] 6.1 Add unit tests for cadence, immediate reconnect send, serialization, heartbeat health, GCJ-02 normalization, lifecycle stop conditions, and cross-order/account isolation.
- [x] 6.2 Add background/lifecycle tests for lock, foreground/background transitions, permission revocation, location gaps, reconnect, and cleanup.
- [x] 6.3 Add WebSocket tests for both peer directions, stale/wrong-order rejection, separation-alert deduplication, and no order-state mutation.
- [x] 6.4 Add track decoding, null/empty/legacy data, primary-route hierarchy, formatting, AMap overlay, anomaly-policy, UI, and accessibility tests.
- [x] 6.5 Run `node scripts/validate-docs.mjs` and `openspec validate enable-live-escort-location-and-track-summary --strict --no-interactive`.
- [x] 6.5.1 Add focused tests for stale-generation rejection, one reconnect, duplicate `NEW_ORDER`, decode diagnostics, retained/presented delivery, reconnect location refresh, and missing-location accessibility feedback.
- [x] 6.5.2 Make blind-runner and volunteer home loading state cancellation-safe and add real-device regression tests for lifecycle/navigation cancellation.
- [x] 6.5.3 Isolate unit/UI-test persistence from the normal app domain, add 20-second generation-safe home refresh recovery, and guard real-device scripts with privacy-safe state hashes plus DemoRelease restoration.
- [x] 6.5.4 Replace animated derived root routing with atomic cancellable `RootRoute` hydration, make home deadlines cancel complete request groups, separate dispatch-summary loading from auxiliary requests, and add privacy-safe network/MetricKit diagnostics plus regressions.
- [x] 6.5.5 Bound volunteer order transitions and their authoritative refresh to a cancellable 12-second deadline, release action UI on unknown outcomes, and add a real-device cancellation regression.
- [x] 6.5.6 Add the release home-map circuit breaker, non-MainActor structured home deadline, non-blocking auxiliary refresh, duplicate-booking guard, privacy-safe run-loop watchdog, and focused regressions.
- [x] 6.5.7 Replace the structured home deadline with a non-blocking race that releases UI even when a client ignores cancellation; keep local blind/volunteer home interactions hittable during loading and cover timeout, late-response rejection, scrolling, panel dragging, refresh, TTS, and navigation on device.
- [x] 6.5.8 Reuse the non-blocking deadline race for volunteer service transitions so a non-cooperative en-route/detail request cannot retain the action spinner or either role's local UI; reject late action responses and cover the permanent-hang regression.
- [x] 6.5.9 Publish validated associated realtime order-status updates before REST recovery, split volunteer POST submission from bounded confirmation, coalesce concurrent home refresh triggers without extending deadlines, and cover duplicate/late events plus permanent confirmation hangs on device.
- [x] 6.5.10 Remove the release home-map circuit breaker, mount one stable AMap per committed role home in Debug/DemoRelease/Production, retain only missing-key/test fallback, and update focused regressions plus documentation.
- [x] 6.5.11 Reconcile WebSocket/REST order status once across home and detail flows, schedule escort/location/map side effects after UI state application, coalesce duplicate sessions and peer-location floods, retain only the newest pending location send, add anonymous phase diagnostics, and cover the en-route hang on both roles with real maps.
- [x] 6.5.12 Retain bounded `ORDER_STATUS_CHANGED` UUID/fingerprint identities across reconnects, reject replay/collision refresh storms, preserve legacy missing-ID compatibility, and suppress parallel lifecycle template TTS after terminal order teardown while retaining REST/polling fallback.
- [x] 6.5.13 Replace dynamic peer-location timelines with one cancellable 15-second expiry task per role, remove the volunteer-home self-referential layout Preference, contain and rate-limit `MAMapView` layout/accessibility churn inside a stable UIKit host, deduplicate location and health publications, gate current-value notification/health TTS replays across SwiftUI subscription rebuilds, preserve arrival-page interaction under hung confirmation, and cover the dual-device high-CPU refresh-loop regression with real maps.
- [ ] 6.6 Run cloud probes and sustained lock/background dual-device validation on `111` and `iPad Pro (2)`, then run the production-readiness scripts before release enablement.
