## 1. Implementation

- [ ] 1.1 Pure moves: `ActiveEmergencyEvent` / `VolunteerEmergencyAlert` → `EmergencyEventModels.swift`; `EmergencyCallContext` → `EmergencyCallContext.swift`
- [ ] 1.2 `ActiveEmergencyEvent.sentAt` / `lastMergedAt`, set on send, countdown fire, merge and recovery
- [ ] 1.3 Copy: reminder 「120或110」; call-options context for the sent screen; since-line formatter; timeline rows
- [ ] 1.4 Screen 3b layout: one primary, one outline, quiet cancel, since line, merge timeline, not-sent order
- [ ] 1.5 Research note `docs/research/sos-sent-screen-patterns-20261022.md` + INDEX row

## 2. Tests and validation

- [ ] 2.1 Unit tests: since-line formatter, sentAt/lastMergedAt bookkeeping, merged copy with the new reminder
- [ ] 2.2 Real-device run of the covering suites with real pass/fail counts
- [ ] 2.3 Real-device screenshots of screen 3b (sent, merged, not sent) exported as test attachments and compared with the mockup
