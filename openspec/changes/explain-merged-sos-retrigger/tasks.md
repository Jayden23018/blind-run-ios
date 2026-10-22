## 1. Implementation

- [x] 1.1 Coordinator: detect same `eventId` → `mergedIntoOpenEvent(status)`; bump `mergedRetriggerCount`
- [x] 1.2 Copy: `EmergencySafetyCopy.mergedIntoOpenEvent`; screen title 「求助已发出」
- [x] 1.3 Screen 3b presented again when `mergedRetriggerCount` changes

## 2. Tests and validation

- [ ] 2.1 `EmergencySOSTests`: merged copy, re-present request, new-id control case, stale `countdownEndsAt` (written and compiled; not yet run on a device)
- [ ] 2.2 Real-device run of the covering suites with real pass/fail counts
