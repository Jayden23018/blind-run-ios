## Context

- Contract (single source): `demo/docs/api_spec.yaml` operations `getRunRecord` / `getMyRunRecords` / `postRunRecordMessage` and schemas `RunRecordResponse`, `RunRecordHistoryResponse`, `RunRecordMessage*`, `Run*`; `demo/docs/websocket-protocol.md` `LOCATION_UPDATE` (v1.2.0). Decisions: `~/Downloads/run-record-handoff/DECISIONS.md` D1–D16 and its change log.
- The backend stores track points (and the new optional fields) **only while the order is `IN_PROGRESS`**, thinned to one point per order-role per 10 s. A dropped message takes its extra fields with it, which is why `steps` must be cumulative.
- iOS has three `LOCATION_UPDATE` senders: `LiveEscortSessionCoordinator` (both roles, `DRIVER_EN_ROUTE`/`DRIVER_ARRIVED`/`IN_PROGRESS`), `ContentView.reportWebSocketLocationIfNeeded` (volunteer idle availability), and `VolunteerLocationReporter` (dispatch accept). Only the first one is live during `IN_PROGRESS`.
- `LocatedCoordinate` carries coordinate + system + time only; horizontal accuracy and speed are dropped at `LocationService.applyDeviceLocation`.
- CoreMotion facts (read from the local iPhoneOS 26.2 SDK headers, 2026-09-24): `CMPedometer.startUpdates(from:)` delivers **cumulative** activity since the given start date, including steps taken while the app was suspended; historical data covers 7 days. `CMPedometerData.currentCadence` is **steps per second** and nil when unavailable. `CMAltimeter.startRelativeAltitudeUpdates` treats the **first update as 0**, so it restarts from zero on every start. Both have `authorizationStatus`.

## Goals / Non-Goals

**Goals:**
- Typed, open-enum-safe models and a service for the three run-record endpoints, backed by real production fixtures.
- Each phone reports its own steps / cadence / relative altitude plus GPS accuracy and speed, in the units the backend expects.

**Non-Goals:**
- Any run-record screen (stage 3 list, stage 4–5 details, stage 6 messages) and any change to the `/track`-based summary.
- Client-side message validation UI (stage 6). The service sends what it is given; the backend is the validator.
- Heart rate, voice messages, admin read (P1 / D12).

## Decisions

### Relationship to `enable-live-escort-location-and-track-summary`
That change (unarchived, all tasks done except real-device dual validation 6.6) owns the escort session: cadence, background location, GCJ-02 boundary, peer markers, alerts, and the `/track` completed summary. This change **plugs into** it rather than forking it:
- The optional fields ride on the coordinator's existing send; no new timer, socket, or sender.
- `lat`/`lng` still go through the one GCJ-02 normalizer; `hAcc`/`speed` are carried alongside the WGS-84 sample through normalization unchanged (they are not coordinates).
- The `/track` summary stays until stage 4 replaces `OrderRouteReplayView` (D13). That later change must MODIFY the adjacent capability's "Completed summary uses the blind track as the run route" requirement — after the adjacent change is archived, so the requirement exists in `openspec/specs/`.

### Where the extra fields come from
- `hAcc`, `speed`: from the same `CLLocation` as `lat`/`lng`, added as optional fields on `LocatedCoordinate`. Negative values (Core Location's "invalid") become nil. Sent in every escort-session update (backend ignores them outside `IN_PROGRESS`); the idle and dispatch senders stay `lat`/`lng` only.
- `steps`, `cadence`, `alt`: a small CoreMotion recorder owned by the escort coordinator, started when the session is `IN_PROGRESS` and stopped in `clearRuntimeSession` / on leaving `IN_PROGRESS`. The coordinator reads the recorder's latest snapshot at send time. Alternative considered: a separate timer sending motion-only messages — rejected, the backend has no such message and thinning would drop it anyway.
- `cadence` = `currentCadence × 60`, rounded; omitted when nil.

### Run start anchor survives relaunch
The run start is the moment this phone first sees the owned order in `IN_PROGRESS`, persisted per order (`UserDefaults`, one record: order id, start date, last reported altitude). On relaunch with the same order id, the stored start is reused, so `startUpdates(from: start)` returns the same cumulative count (CMPedometer backfills from system history). Alternative considered: backend `IN_PROGRESS` time from `/status-logs` — more exact but one more request and one more failure path; the local anchor's error is only the latency between the status change and this phone learning about it (≤ one 5 s poll / one WS push).

### Altitude continuity
Because the altimeter restarts at 0, the recorder reports `baseline + relativeAltitude`, where `baseline` is the last altitude reported for the same order (0 on a fresh run). Without it an upward jump after a relaunch (e.g. −8 → 0) would be counted by the backend as 8 m of climb.

### Permission timing (project owner, 2026-09-24)
Request Motion & Fitness when the escort session reaches `DRIVER_EN_ROUTE` on either phone, using a zero-length `queryPedometerData(from: now, to: now)` only when `CMPedometer.authorizationStatus() == .notDetermined`. At that point nobody is running yet; triggering it at `IN_PROGRESS` would steal VoiceOver focus as the run starts. No in-app explainer screen in this stage; the `NSMotionUsageDescription` string carries the explanation.

### Keeping hardware out of tests
The recorder is injected into the coordinator. The production recorder is a no-op under `XCTestConfigurationFilePath` (same rule as `RunLiveActivityController.isRunningUnderXCTest`). The coordinator only starts it when a `WebSocketService` is attached, which never happens in the Mock environment, so UI tests in Mock never see a system prompt.

### Open enums
Same pattern as `RunOrderStatus` / `PacePreference`: `case unknown` + a tolerant `init(from:)`. Arrays that the contract says to skip (`events`, `messages` by type) decode element-wise and drop unknowns; a malformed element of those arrays is also dropped rather than failing the record. Dates stay `String`, matching `OrderTrackModels`.

### Service without a production caller yet
`IncentiveServing` documents "every method must have a production call site". This stage deliberately ships the service before its screens (stages 3–6 are the callers). The protocol comment names the stage that will call each method, so an unused method is visibly pending rather than dead.

## Risks / Trade-offs

- [Motion prompt timing can only be observed on a real device] → manual check on device during stage-2 validation; if the zero-length query does not trigger the prompt, fall back to starting pedometer updates at `DRIVER_EN_ROUTE`.
- [Local run anchor starts a few seconds late on the phone that did not press "start service"] → worst case a few steps missing at the start; totals are per phone anyway (D3).
- [Blind phone never sees `IN_PROGRESS` because the app was not running] → no motion for that run; backend returns null and the UI hides the fields (HANDOFF 6.4). Same limit as location capture today.
- [Pedometer and altimeter drain battery] → run only during `IN_PROGRESS`, stopped with the escort session.
- [No real message in production to capture] → message decoding is covered by handwritten tests; the capture script stays read-only by design.
