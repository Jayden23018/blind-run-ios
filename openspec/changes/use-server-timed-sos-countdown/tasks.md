## 1. Implementation

- [x] 1.1 Models: `useCountdown`, `countdownEndsAt`, `COUNTDOWN` / `CANCELLED`
- [x] 1.2 Coordinator: locate → trigger(useCountdown) → server countdown; withdraw via cancel; recovery resumes
- [x] 1.3 Copy and states: withdrawn / withdraw failed; screen titles
- [x] 1.4 Countdown screen: async cancel with loading; Mock plays the server countdown

## 2. Tests and validation

- [x] 2.1 `EmergencySOSTests` rewritten for the server countdown
- [x] 2.2 Real-device run of the covering suites with real pass/fail counts
- [ ] 2.3 Real-device listening check: long press → countdown → cancel, and let it run out (needs a person, see PR)
