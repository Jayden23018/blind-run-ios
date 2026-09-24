## 1. Tokens and test hooks

- [x] 1.1 Add D8 palette to `AppColors` with dark variants; contrast checks in `LowVisionChannelTests`
- [x] 1.2 DEBUG-only `AIDRUN_UI_TEST_COLOR_SCHEME` launch setting
- [x] 1.3 Mock: multi-point thumbnails in monthly history; UI-test-only history seed with a cancelled order

## 2. Records tab

- [x] 2.1 Shared `RunRecordHistoryViewModel` (monthly + unfinished, month switching, summaries, labels, error/retry)
- [x] 2.2 Shared `RunRecordHistoryView(role:)` with loading / empty / error states, rotor, 64pt rows
- [x] 2.3 `RunRouteThumbnail` path normalisation
- [x] 2.4 Replace `BlindRunHistoryView` and `VolunteerServiceRecordsView` at every caller; rename the volunteer profile entry

## 3. Tests and validation

- [x] 3.1 Unit tests for the view model, labels, null handling, month arithmetic, thumbnail normalisation (replace `BlindRunHistoryTests`)
- [x] 3.2 Update UI tests that assert the old titles; add a screenshot test for both roles
- [ ] 3.3 Real-device run of the suites covering the change, real pass/fail counts
- [ ] 3.4 Real-device screenshots: light, dark, largest text size, both roles
- [x] 3.5 Append stage-3 decisions to `DECISIONS.md` change log
