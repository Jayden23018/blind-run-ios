## Why

The backend now computes one post-run record per completed order (backend PR #301, migration `0047`, live in production since 2026-09-24): route, splits, pace samples, rests, events, service minutes, messages, and a monthly history. The iOS app can neither read these records nor feed them the per-phone motion data (steps, cadence, relative altitude) and GPS quality fields they depend on. Stage 2 of the post-run record plan (`~/Downloads/run-record-handoff/DECISIONS.md`) lays that data foundation so the UI stages (3–6) have typed, contract-checked data to build on.

## What Changes

- Add typed models for `GET /api/orders/{id}/run-record`, `GET /api/orders/mine/run-records?month=YYYY-MM`, and `POST /api/orders/{id}/run-record/messages`. Response-side enums (`status`, `viewerRole`, `fromRole`, message `type`, event `type`, history `role`) are open: an unknown value never fails the whole response; unknown events and unknown message types are skipped.
- Add a run-record endpoint + service + in-process Mock behavior following the existing `Endpoint → Service → transport.send` pattern, plus real-response fixtures captured from production.
- Extend both roles' `LOCATION_UPDATE` with the optional `hAcc`, `speed`, `alt`, `steps`, `cadence` fields (DECISIONS D10). `steps` is cumulative since the run started on this phone, `cadence` is steps per minute, and fields that are unavailable are omitted (never sent as `0`).
- Collect steps, cadence, and barometric relative altitude on **both** phones (D3) during `IN_PROGRESS`; request Motion & Fitness permission on both roles when the escort session starts (`DRIVER_EN_ROUTE`), not at run start.
- No user-visible screen changes in this stage (list, detail, and message UIs are stages 3–6). The only new visible surface is the system Motion & Fitness permission prompt.

## Capabilities

### New Capabilities

- `post-run-record`: Reading post-run records and monthly history, posting run messages, and the per-phone motion/GPS-quality data the phone contributes to those records during a run.

### Modified Capabilities

None. The overlapping capability `live-escort-location-and-track-summary` belongs to the unarchived change `enable-live-escort-location-and-track-summary` and has no main spec yet, so it cannot be delta'd here; the division of responsibility is stated as a requirement in `post-run-record` instead (see design.md → "Relationship to enable-live-escort-location-and-track-summary").

## Impact

- iOS data layer: new run-record models, endpoint, service, `AppState` accessor, Mock routes, contract fixtures, `ContractFixtureTests` checkers, `scripts/capture-fixtures.mjs`.
- iOS runtime: `WSLocationUpdateMessage` optional fields, location samples carry horizontal accuracy and speed, a CoreMotion recorder owned by the live escort session, `Info.plist` `NSMotionUsageDescription`.
- Backend contract: consumed as-is (`demo/docs/api_spec.yaml` `getRunRecord` / `getMyRunRecords` / `postRunRecordMessage`, `demo/docs/websocket-protocol.md` `LOCATION_UPDATE` v1.2.0). No contract change requested.
- Privacy: step, cadence, and altitude are sent only inside the existing authenticated escort session while `IN_PROGRESS`; the backend returns each viewer only their own phone's motion data.
- Battery: CoreMotion pedometer and altimeter run only during `IN_PROGRESS` and stop with the escort session.
