## Why

Issue #795. Blind runners type with the on-screen keyboard at 0.66–4 words per minute (research `docs/research/blind-input-reduction-20261106.md`).
The booking form already has dictation on its four text fields (`VoiceTextField`), but four other free-text fields do not:
the message to the volunteer, the review comment, the report detail, and the support ticket.
`SpeechInputField.ratingFeedback` was defined for the review comment and never used.

The owner decided on 2026-11-06 that dictation uses Apple's on-device framework (`SFSpeechRecognizer`) and does not send this text to the backend language model.

## What Changes

- Add a reusable dictation button (`VoiceDictationButton`) under an existing text editor. The editor keeps its current look.
- The button is a full-width secondary button, so it is easy to find and press. It says "语音输入" and changes to "停止语音输入" while recording.
- Recognized text is appended to what was in the field when recording started. It does not replace text the user already typed.
- When recognition ends with text, the app announces "已填入：<recognized text>". Research shows blind users spend most of their dictation time checking results, so the result is read back once.
- Use it in four places: runner message, review comment (`.ratingFeedback`), report detail, support ticket. The last two are shared with the volunteer side.
- No change to submission, length limits, or the backend.

## Impact

- New `blindRun/Voice/VoiceDictationButton.swift`.
- `blindRun/Voice/SpeechInputService.swift`: three new `SpeechInputField` cases.
- `blindRun/BlindRunner/RunnerMessage.swift`, `blindRun/BlindRunner/BlindOrderStatusView+StatusSections.swift`, `blindRun/Shared/UserReportView.swift`, `blindRun/Shared/SupportTicketView.swift`.
- Tests in `blindRunTests/VoiceAndSpeechInputTests.swift`.
