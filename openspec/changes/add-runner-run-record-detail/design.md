## Context

Data: `RunRecordResponse` (contract `demo/docs/api_spec.yaml` `getRunRecord`), same as stage 4. For the runner, `comparison` is present when there is a previous finished run, steps / cadence / climb are the runner's own phone (D3), `service.volunteerTotalServiceMinutes` is the volunteer's cumulative service time (D6). `stops[].placeName` is always null this release.

Audio: the app configures the session once at launch as `.playback` / `.spokenAudio` / `.duckOthers` (`SystemSpeechAudioSession.configurePlaybackCategory`), which is what HANDOFF §6.3 asks for, so this change does not touch the session.

## Decisions

- **One view model for both roles**: stage 4's `VolunteerRunRecordViewModel` (load, 2 s `GENERATING` re-read, retry) is role-agnostic; it moves to `RunRecordPresentation.swift` as `RunRecordViewModel`.
- **Narration synthesizer**: a page-owned `AVSpeechSynthesizer` with `prefersAssistiveTechnologySettings = true` (same utterance factory as `VoiceService.makeUtterance`). `VoiceService.speak` is not used because it also posts a VoiceOver announcement, which would read the whole narration twice. Starting playback calls `VoiceService.stop()` first.
- **Narration text** (template, HANDOFF §6.3 item 2): "{M月d日}，{星期}{时段}{H点m分}，你和{搭档}在{地点}跑了{X}公里，运动时间{…}，平均{每公里…}，比上一次多跑了/少跑了{X}公里。" + slowest and fastest full kilometre (only when there are at least two full kilometres and they differ) + each rest ("跑到{X}公里处，你们停下来休息了{…}。") + cadence ("全程步频很稳，平均每分钟{N}步。" when max − min split cadence ≤ 5, otherwise "平均步频每分钟{N}步。") + the latest volunteer message ("{名}给你留了一句话：{text}"). Missing values drop their clause. Time of day: 0–5 凌晨, 5–9 早上, 9–12 上午, 12–14 中午, 14–18 下午, 18–24 晚上. Names are read without mask asterisks.
- **Sonification** (project owner, 2026-09-25): a stereo 16-bit WAV rendered on a background task and played with one `AVAudioPlayer` held for the page's lifetime (memory `finishedplaying-crash-means-player-freed-not-delegate`).
  - Time: 0.45 s per 100 m; if that exceeds 45 s the rate shrinks so the run fits 45 s. Rests add 1.1 s each.
  - Pitch: pace → fraction via `RunPaceScale` (p5…p95), frequency = 760 · 0.5^fraction (380–760 Hz, one octave, log so equal steps sound equal). Triangle wave through a first-order low-pass (1.6 kHz), level 0.25.
  - Pan: track longitude normalised to the route's west…east extent → −0.9…+0.9, equal-power. No track → centre.
  - Kilometre N: N beeps of 1250 Hz, 0.12 s each, 0.14 s apart. Rest: tone fades out over 0.25 s, one 190 Hz beep, fades back in 1.1 s later. End: 880 Hz then 1320 Hz.
  - Progress ("第 N 公里", bar strip) is derived from `player.currentTime` against the rendered timeline; no VoiceOver announcements while playing (HANDOFF: "拿不准就只做屏幕文字").
  - No pace samples → the section is hidden.
- **Mutual exclusion and focus**: one `RunRecordAudioController` owns both players. Starting either stops the other and `VoiceService`. `UIAccessibility.elementFocusedNotification` whose focused element is not the active control pauses it; the control's label becomes "继续…"; activating it resumes. Leaving the page stops everything.
- **Order**: VoiceOver on → header, listen, sound route, splits, route (map hidden from VoiceOver + visible text description), more data, order link. VoiceOver off → stage-4 pace map on top, rest unchanged. Initial VoiceOver focus goes to the header via `@AccessibilityFocusState` once the record loads.
- **Route description** (MVP template): stage-4 description (distance, start/end coincide, rests) + "最远跑到起点{八方位}约{X}公里处" from the farthest track point.
- **Cumulative service time** (D6): one row in "更多数据": "{名}累计陪跑 {X 小时 Y 分钟}". Not in header or narration.
- **Split rows**: "第3公里，5分58秒，本次最快，步频每分钟171步。"; the last partial split: "最后0.2公里，用时1分16秒，折合每公里6分20秒". Screen text uses the same Chinese wording, never `6'15"`.

## Risks

- Audio correctness (pitch, pan direction, beep counts, VoiceOver interplay) cannot be verified by code; the project owner listens on a real device.
- A `VoiceService` status announcement arriving mid-narration plays on its own synthesizer and overlaps; this page does not suppress global announcements.
- Archive order: this change's MODIFIED delta targets a requirement also modified by `add-volunteer-run-record-detail`.
