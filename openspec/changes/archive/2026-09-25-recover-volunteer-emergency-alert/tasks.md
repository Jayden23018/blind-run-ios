## 1. Implementation

- [x] 1.1 `EmergencyCoordinator.refreshVolunteerAlert`: restore / acknowledge / clear, skip `COUNTDOWN`
- [x] 1.2 `AppState.recoverActiveEmergency` by role; called from catch-up and after cold-start restore
- [x] 1.3 Decode `distanceMeters` / `distanceBand`, carry the usable server distance to the alert, `VolunteerEmergencyAlert.distanceText`

## 2. Tests and validation

- [x] 2.1 Unit tests `VolunteerEmergencyRecoveryTests`
- [x] 2.2 Real-device run of `VolunteerEmergencyRecoveryTests`, `EmergencySOSTests`, `NotificationCatchUpTests` with real pass/fail counts
