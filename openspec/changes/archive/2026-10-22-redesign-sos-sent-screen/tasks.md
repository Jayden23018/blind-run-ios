## 1. Implementation

- [x] 1.1 Pure moves: `ActiveEmergencyEvent` / `VolunteerEmergencyAlert` → `EmergencyEventModels.swift`; `EmergencyCallContext` → `EmergencyCallContext.swift`
- [x] 1.2 `ActiveEmergencyEvent.sentAt` / `lastMergedAt`, set on send, countdown fire, merge and recovery
- [x] 1.3 Copy: reminder 「120或110」; call-options context for the sent screen; since-line formatter; timeline rows
- [x] 1.4 Screen 3b layout: one primary, one outline, quiet cancel, since line, merge timeline, not-sent order
- [x] 1.5 Research note `docs/research/sos-sent-screen-patterns-20261022.md` + INDEX row

## 2. Tests and validation

- [x] 2.1 Unit tests: since-line formatter, sentAt/lastMergedAt bookkeeping, merged copy with the new reminder
- [x] 2.2 Real-device run of the covering suites with real pass/fail counts (EmergencySentScreenTests + EmergencyMergedRetriggerTests + EmergencySOSTests + PreciseLocationGateTests: passed=104 failed=0)
- [x] 2.3 Real-device screenshots of screen 3b (sent, merged, not sent) exported as test attachments and compared with the mockup
