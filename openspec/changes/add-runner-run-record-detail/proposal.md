## Why

Stage 4 gave volunteers the post-run detail; a blind runner who opens a finished run still lands on the order page and, behind its link, the `/track` replay (`OrderRouteReplayView`): a map they cannot see and three numbers. HANDOFF §6.3 (P0 part) asks for a page a runner can take in without looking: a spoken narration, the route as sound, one sentence per kilometre, and the remaining numbers. Stage 5 of `~/Downloads/run-record-handoff/DECISIONS.md` builds it and, per D13, deletes `OrderRouteReplayView`.

## What Changes

- New runner post-run detail page fed by `RunRecordServing.record(orderId:)`, in HANDOFF §6.3 order: header (one accessibility element: date and time of day, partner, place, distance, moving time, average pace, comparison with the previous run), "听这次跑步" (tactile-yellow, ≥96pt, narration with its transcript), "用声音走一遍路线" (sonification), "每一公里", "路线" (map + text description), "更多数据" (steps, cadence, climb, rest, total time, and — D6 — the volunteer's cumulative service time), then a link "订单详情与评价" to the existing order page.
- VoiceOver on: focus lands on the header on entry, so one swipe right reaches "听这次跑步"; the map sits in "路线" and is hidden from VoiceOver (its text description is read instead). VoiceOver off: the stage-4 pace map sits on top (the high-contrast map is P1). Switches live on `voiceOverStatusDidChangeNotification`.
- No `6'15"` anywhere on this page, screen or speech (HANDOFF 5.3).
- Narration: its own `AVSpeechSynthesizer` (not `VoiceService.speak`, which also posts a VoiceOver announcement and would read a 35-second text twice), user's VoiceOver voice and rate; ends with the latest volunteer message if there is one.
- Sonification (project owner, 2026-09-25): rendered offline into a stereo WAV with the existing `ToneSynthesizer` approach and played with `AVAudioPlayer` — no `AVAudioEngine`, no change to the audio session. 0.45 s per 100 m, total capped at 45 s; triangle wave 380–760 Hz (faster = higher, log scale over the p5–p95 pace range); pan follows east–west position; N short 1250 Hz beeps at kilometre N; fade out + 190 Hz tone at each rest; two rising tones at the end. On screen only: "第 N 公里" and the bar strip lighting up. No VoiceOver announcements during playback.
- Narration, sonification and VoiceOver do not talk over each other: starting one stops the other and the app's own TTS; VoiceOver focus leaving the control pauses it, activating it again resumes.
- Entry points: the runner's records-tab row and the "查看跑后详情" link in `CompletedTrackSummaryView` on the runner order page open the new page (project owner, 2026-09-25). Reviews stay on the order page, reached from the new page's last row.
- `OrderRouteReplayView` is deleted; `TrackRouteMap` / `TrackStatsRow` (still used by the inline summary) move into `CompletedTrackSummaryView.swift`.
- States per HANDOFF §6.4, same as stage 4.

Not in this change: high-contrast low-vision map, "分享给家人", rest-place names (P1); the "小林的留言" section, "朗读留言" and replies (stage 6).

## Capabilities

### New Capabilities

- `runner-run-record-detail`: what the runner post-run detail shows, its speech and sound, every state, and its accessibility contract.

### Modified Capabilities

- `live-escort-location-and-track-summary`: "Completed summary uses the blind track as the run route" — the runner's full-screen route view becomes the runner post-run detail; the track-based replay is gone.
  ⚠️ That capability is still an unarchived delta in `enable-live-escort-location-and-track-summary`, and `add-volunteer-run-record-detail` modifies the same requirement. **Archive order: `enable-live-escort-location-and-track-summary` → `add-volunteer-run-record-detail` → this change.**

## Impact

- iOS UI: new `BlindRunner/RunnerRunRecordView.swift`, `Shared/RunRecordAudio.swift`; `Shared/RunRecordPresentation.swift` (view model moves here, renamed `RunRecordViewModel`), `Shared/CompletedTrackSummaryView.swift`, `Shared/RunRecordHistoryView.swift`, `BlindRunner/BlindOrderStatusView.swift`, `Volunteer/VolunteerRunRecordView.swift` (map made reusable); `Shared/OrderRouteReplayView.swift` deleted; `Voice/SpeechInputService.swift` (`ToneSynthesizer.container` no longer private — `SystemSpeechAudioSession` untouched).
- Mock: a seeded volunteer message for the runner's record.
- Backend contract: consumed as-is. `postMessage` stays uncalled until stage 6.
