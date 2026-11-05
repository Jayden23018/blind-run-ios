## Why

Stages 4 and 5 show the post-run detail to both sides, but the message channel (D7: separate from the review, visible to both) has no way in: `RunRecordServing.postMessage` has no caller, the volunteer page shows existing messages read-only, and the runner only hears the latest volunteer message at the end of the narration. HANDOFF §8 P0 asks for "陪跑员文字留言，以及跑者端朗读". Stage 6 of `~/Downloads/run-record-handoff/DECISIONS.md`.

## What Changes

- Volunteer detail: a "给X留句话" section with a text box (1–200 characters after trimming, counted like the backend's `@Size` — UTF-16 units), three quick phrases from the prototype ("节奏很稳" / "下次试试再快一点" / "折返配合得很好", each fills the box with the phrase and "。"), and a send button. Blank or too long is rejected on the client with a visible and spoken reason. While sending the button is disabled and says so; on success the box clears, the message joins the list and the page says "已发送。X在这条跑步记录里可以听到这句话。" (project owner, 2026-09-25: the prototype's "打开这条记录时会听到" is not what the runner page does); on failure the draft stays and the reason is shown and spoken. More than one message per run is allowed (project owner).
- Partner deregistered (`blindName` is null): no composer; the page says "对方已注销账号，留言无法送达。" Existing messages stay (project owner).
- Runner detail: a "X的留言" section between "每一公里" and "路线" with every volunteer message as text and a "朗读留言" button. It uses `RunRecordAudioController` — mutually exclusive with the narration and the sound route, paused when VoiceOver focus leaves it. No section when there is no volunteer message.
- No reply control on the runner side in P0 (project owner, 2026-09-25): the voice reply is P1, and a runner text composer is not asked for.
- No push or local notification after sending (backend does not push this period). No wording about how long a message is kept (retention is undecided on the backend).

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `volunteer-run-record-detail`: "Pace chart, splits and timeline carry the numbers" loses its "Existing messages — no composer" scenario; a new requirement adds the composer.
- `runner-run-record-detail`: new requirement for the message section and "朗读留言".
  ⚠️ Both capabilities are still unarchived deltas (`add-volunteer-run-record-detail`, `add-runner-run-record-detail`). **Archive after both of them.**

## Impact

- iOS UI: `Shared/RunRecordPresentation.swift` (send state, draft validation, merged message list), `Shared/RunRecordAudio.swift` (`.message` source), `Volunteer/VolunteerRunRecordView.swift`, `BlindRunner/RunnerRunRecordView.swift`.
- Mock: `handlePostRunRecordMessage` counts characters like the backend.
- Backend contract: `postRunRecordMessage` consumed as-is.
