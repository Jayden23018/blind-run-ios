## 1. Implementation

- [x] 1.1 Coordinator: detect same `eventId` → `mergedIntoOpenEvent(status)`; bump `mergedRetriggerCount`
- [x] 1.2 Copy: `EmergencySafetyCopy.mergedIntoOpenEvent`; screen title 「求助已发出」
- [x] 1.3 Screen 3b presented again when `mergedRetriggerCount` changes

## 2. Tests and validation

- [ ] 2.1 `EmergencyMergedRetriggerTests`: merged copy, re-present request, new-id control case, stale `countdownEndsAt` (written and compiled; not yet run on a device)
- [ ] 2.2 Real-device run of the covering suites with real pass/fail counts
- [ ] 2.3 Real-device manual check: press SOS, tap 「返回跑步」, wait over 60 s, press again → screen 3b comes back with the merged copy (UI tests cannot reach the sent state, see Jayden23018/blind-run-ios#500)
