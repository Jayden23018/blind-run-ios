## 1. Run-record data access

- [x] 1.1 Add run-record models (`RunRecordResponse`, `RunRecordHistoryResponse`, `RunRecordMessage*`, nested `Run*`) with open enums and skip-unknown `events` / `messages`
- [x] 1.2 Add `RunRecordEndpoint` + `RunRecordServing` / `RunRecordService` + `AppState.runRecord`
- [x] 1.3 Add Mock routes for the three endpoints (completed-order gate, month filter, message append)
- [x] 1.4 Unit tests: open-enum fallback, unknown event/message skipped, nulls stay nil, request shapes, Mock behavior

## 2. Contract fixtures

- [x] 2.1 Extend `scripts/capture-fixtures.mjs` with run-record (runner READY, volunteer READY, runner INSUFFICIENT_TRACK) and monthly history (both roles)
- [x] 2.2 Capture from production and review redaction
- [x] 2.3 Add `ContractFixtureTests` checkers for `RunRecordResponse` and `RunRecordHistoryResponse`

## 3. Location update extra fields

- [x] 3.1 Carry horizontal accuracy and speed on `LocatedCoordinate` through normalization
- [x] 3.2 Add optional `hAcc` / `speed` / `alt` / `steps` / `cadence` to `WSLocationUpdateMessage`, omitted when nil
- [x] 3.3 CoreMotion recorder: persisted per-order run anchor, cumulative steps, cadence ×60, altitude baseline continuity, XCTest no-op
- [x] 3.4 Wire recorder into `LiveEscortSessionCoordinator`: permission request at `DRIVER_EN_ROUTE`, start/stop around `IN_PROGRESS`, attach snapshot on send
- [x] 3.5 `NSMotionUsageDescription` in `Info.plist`
- [x] 3.6 Unit tests: encoding omits nil / never 0, cadence unit, anchor reuse on relaunch, altitude baseline, coordinator start/stop

## 4. Handoff and validation

- [x] 4.1 Answer `demo/docs/handoff.md` 2026-09-24「待前端确认」item 1
- [x] 4.2 Real-device run with real pass/fail counts (scope changed 2026-09-24 by the project owner: run only the suites covering the change, never full; failures compared against an `origin/main` baseline)
- [x] 4.3 Append stage-2 decisions to `DECISIONS.md` change log
