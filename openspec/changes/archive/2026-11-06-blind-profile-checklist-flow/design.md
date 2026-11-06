## Context

#784 (merged 2026-11-06) added `BlindRunnerProfileViewModel.saveChange(savedLabel:revert:)`. That method sends the whole profile with `PUT /api/blind/profile`. It also brings back `runningPace` and `specialNeeds`, because a missing key clears the value. Consent, decline and withdraw already live in the view model. See proposal.md for why.

## Goals / Non-Goals

**Goals:** reuse the #784 save path; keep old free text; make each card one save.

**Non-Goals:** no backend change; no change to consent text or `disclosureVersion`; no voice input for the nickname (#796 keeps that item).

## Decisions

- **Answers live in the flow until "完成".** The sheet keeps a draft. On "完成", one view-model call writes the fields and saves. If the save fails, a snapshot puts the old values back. Alternative: write each answer into the view model as the runner picks it. Rejected, because closing the sheet would then leave unsaved values on screen.
- **Phrase join and read-back is a pure function** (`BlindProfilePhrases`). The single-choice phrase comes first, then the multi-choice phrases in a fixed order, then the supplement. All parts are joined with "；". On read-back, the app splits on "；". Segments that match a phrase exactly are selected. All other segments are joined back with "；" in their original order and become the supplement. This keeps old text, and unit tests can cover it without UI.
- **"Set" status comes from stored data, not from local flags.** For this reason, every option on the 路况播报 question stores a phrase ("详略均可" is also stored), and 其他需求 has the exclusive option "无其他需求". Without this, a saved card can still show "尚未设置".
- **Consent screen inside the sheet** uses `PrivacyConsentPurpose.blindVisionProfile.title`, `.disclosures`, `.agreeButtonTitle` and `.declineButtonTitle` directly. It does not copy their text.
- **Decline saves at once.** It uses the same `NOT_SPECIFIED` request that #784 sends after a decline, and speaks the existing decline feedback. The card stays under "未设置": existing profiles were all back-filled with `NOT_SPECIFIED`, so that value cannot tell "declined" from "never asked".

## Risks / Trade-offs

- [The stored text changes shape for old users after their first save. Segments are trimmed, and segments joined with other separators stay as one supplement.] → No text is dropped. The supplement keeps the original order.
- [A supplement that is exactly a phrase becomes a selected option.] → The text in the field is the same, and only the order can change.
- [The UI and audit tests are not run.] → They compile in `build-for-testing`. The owner checks the app on a device.
