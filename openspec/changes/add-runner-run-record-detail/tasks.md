## 1. Shared pieces

- [ ] 1.1 Move the record view model to `RunRecordPresentation.swift` as `RunRecordViewModel`; make the stage-4 route map reusable
- [ ] 1.2 `RunnerRunRecordContent`: header sentence, narration, split rows, more-data rows, route description (pure, unit-tested)
- [ ] 1.3 `RunRouteSonification`: timeline and stereo WAV rendering (pure, unit-tested)
- [ ] 1.4 `RunRecordAudioController`: narration synthesizer + sonification player, mutual exclusion, pause on VoiceOver focus change

## 2. Page and entries

- [ ] 2.1 `RunnerRunRecordView`: §6.3 order, VoiceOver-dependent map position, initial focus on the header, all §6.4 states, "订单详情与评价" link
- [ ] 2.2 Entry points: runner records-tab row and the runner order page's summary link; delete `OrderRouteReplayView`, move `TrackRouteMap` / `TrackStatsRow`
- [ ] 2.3 Mock: seeded volunteer message on the runner's record

## 3. Tests and validation

- [ ] 3.1 Unit tests for content, sonification timeline, audio controller state
- [ ] 3.2 UI test: detail opens from the records tab, header → listen order, audit at the top; screenshot test (light, dark, largest text, real map)
- [ ] 3.3 Real-device run of the covering suites, real pass/fail counts
- [ ] 3.4 Append stage-5 decisions to `DECISIONS.md`
- [ ] 3.5 Archive only after `enable-live-escort-location-and-track-summary` and `add-volunteer-run-record-detail` are archived (leave this box open until then)
