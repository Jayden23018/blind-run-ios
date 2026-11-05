## Context

`postRunRecordMessage` (demo `origin/main`): either participant, only once the order is `COMPLETED`, `type` = `TEXT`, `text` stripped then stored, 1–200. Backend validation is `@NotBlank` + `@Size(max = 200)` on the raw string (Java `String.length()` = UTF-16 units). Errors: 400 `VALIDATION_ERROR` / `BAD_REQUEST`, 403 `NOT_ORDER_PARTICIPANT`, 404 `ORDER_NOT_FOUND`, 409 `ORDER_STATUS_NOT_ALLOWED`. The backend accepts a message to a deregistered partner (201) — nobody will read it.

## Decisions

- **Client sends the trimmed text** and checks 1…200 UTF-16 units on it, so the raw-string validation on the backend sees the same thing the client counted.
- **Send state lives in the shared `RunRecordViewModel`** (idle / sending / sent / failed(reason)); sent messages are kept there and merged into the record's list by `id`, so a `GENERATING` re-read cannot duplicate them. The draft is view state.
- **Failure wording** always starts with "留言没有发出。" then the reason: network → "请检查网络后再发一次。"; 409 → "这一单还没完成，暂时不能留言。"; 403 → "你不是这一单的参与者。"; 404 → "这一单已经不存在了。"; anything else → the error's own message. Spoken with `speakError` (same as other volunteer view models); success is posted as a VoiceOver announcement.
- **"朗读留言"** reads "X的留言：" + every volunteer message in order, through the controller's synthesizer (source `.message`), so it shares the stop / pause / focus rules of the narration.

## Risks

- Listening quality (voice, pauses, interruption by VoiceOver) can only be checked by ear on a device.
