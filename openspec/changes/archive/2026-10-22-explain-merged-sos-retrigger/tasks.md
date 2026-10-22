## 1. Implementation

- [x] 1.1 Coordinator: detect same `eventId` → `mergedIntoOpenEvent(status)`; bump `mergedRetriggerCount`
- [x] 1.2 Copy: `EmergencySafetyCopy.mergedIntoOpenEvent`; screen title 「求助已发出」
- [x] 1.3 Screen 3b presented again when `mergedRetriggerCount` changes

## 2. Tests and validation

- [x] 2.1 `EmergencyMergedRetriggerTests`: merged copy, re-present request, new-id control case, stale `countdownEndsAt` (red on `91fca348`: passed=2 failed=1, the merged-copy case)
- [x] 2.2 Real-device run of the covering suites with real pass/fail counts (EmergencyMergedRetriggerTests + EmergencySOSTests + PreciseLocationGateTests: passed=87 failed=0)
- [x] 2.3 Deferred by the project owner on 2026-10-22 (it needs the real backend, which sends real SOS SMS). Tracked in Jayden23018/blind-run-ios#500. Original check: press SOS, tap 「返回跑步」, wait over 60 s, press again → screen 3b comes back with the merged copy (UI tests cannot reach the sent state, see Jayden23018/blind-run-ios#500)
