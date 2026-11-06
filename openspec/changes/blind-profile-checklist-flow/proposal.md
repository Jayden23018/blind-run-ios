## Why

On 2026-11-06 the owner found the blind runner's profile page still felt like a form. The owner approved a checklist design (#812): the runner picks options and does not type. The design copies Apple Health's "Health Checklist". The vision consent entry moves, so this is a privacy change and needs a spec.

## What Changes

- The profile page shows five cards: 陪跑方式, 视力状况与导盲犬, 途中提示, 其他需求, 紧急联系人. Cards are split into "未设置" and "已设置".
- Each card except 紧急联系人 opens a sheet with one question per screen. The app saves the whole card once, when the runner presses "完成" on the last question. Closing the sheet saves nothing.
- The two free-text fields (`guidePreferenceText` ≤ 80, `specialNeeds` ≤ 500) become multi-choice common phrases plus one optional supplement line with voice input. The app joins them with "；" into the same field. The backend does not change.
- Text that the app cannot match to a phrase goes into the supplement line, so old text is never lost.
- The vision consent screen becomes the first screen of the vision card. Declining saves both fields as `NOT_SPECIFIED` at once. The withdraw action moves onto the vision card.
- Choice pages from #784 are removed. The nickname edit page stays.
- All copy uses formal wording (approved by the owner on 2026-11-06).

## Capabilities

### New Capabilities

### Modified Capabilities
- `blind-profile-page`: The overview, choice pages and text pages are replaced by checklist cards and a one-question-per-screen flow. The vision consent entry and the withdraw action move.

## Impact

- Code: `blindRun/Profile/` (new card, flow and phrase files; `ProfileModule.swift`; remove `BlindProfileChoicePage.swift`).
- Tests: new `BlindProfilePhrasesTests`; UI and audit tests follow the new identifiers. Tests are written and compiled, not run (owner decision on 2026-11-05).
- API: none. The app still sends the whole profile with `PUT /api/blind/profile`.
- Privacy: the consent text and the two buttons are taken word for word from `PrivacyConsentPurpose.blindVisionProfile`. `disclosureVersion` does not change.
