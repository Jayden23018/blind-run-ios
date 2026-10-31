## 1. Walk-through

- [x] 1.1 Walk HANDOFF §7's nine checks on the four screens; record pass / fail / manual-only with evidence in `docs/review/run-record-accessibility-audit-20261028.md`
- [x] 1.2 Records tab Dynamic Type audit: false positive or real, with evidence from the same run's largest-text screenshots

## 2. Fixes

- [x] 2.1 Volunteer detail: navigation title read without mask markers
- [x] 2.2 Map: "快 ▬ 慢" legend (both details), hidden from VoiceOver; volunteer description adds colour meaning and fastest kilometre
- [x] 2.3 Pace chart spoken summary adds rests
- [x] 2.4 Send button hint

## 3. Tests and validation

- [x] 3.1 Unit tests for the map description and chart summary
- [x] 3.2 UI tests: no mask markers in any label on the four screens, no apostrophe pace on the runner detail
- [x] 3.3 Real-device run of the covering suites, real pass/fail counts
- [ ] 3.4 Screenshots on a real device: light, dark, largest text, Increase Contrast
- [x] 3.5 Append stage-7 decisions to `DECISIONS.md`
- [ ] 3.6 Archive only after `add-volunteer-run-record-detail`, `add-runner-run-record-detail` and `add-run-record-messages` are archived (leave open until then)
