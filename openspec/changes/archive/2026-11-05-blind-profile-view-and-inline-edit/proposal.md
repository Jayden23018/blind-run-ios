## Why

The blind runner's profile page opens as one long form with a Save button at the bottom. A VoiceOver user has to swipe through every field to change one value, and the page does not say which fields a volunteer sees at dispatch time and which only after acceptance. The owner approved a redesign on 2026-11-05 ("按推荐开工"): look first, then tap a row to change only that row (Jayden23018/blind-run-ios#750).

## What Changes

- The profile page opened from the account page becomes a read-only overview. It shows the avatar, the name and "视障跑者", then grouped cards: nickname; "派单时，陪跑员就会看到" (guidance, default pace); "接单后，陪跑员才看到" (note to the volunteer, special needs); "视力状况（敏感个人信息）"; and a one-row emergency-contact summary that opens `EmergencyContactsView`.
- Option rows (guidance, default pace, vision, guide dog) push a choice page. Each choice is one 64pt row with a check mark. A tap saves the whole profile at once with `PUT /api/blind/profile`. Success speaks and shows "已保存：<choice>" in green. Failure speaks the error and moves the check mark back to the old value.
- Text rows (nickname, note to the volunteer, special needs) push an edit page with a Save button at the bottom. Success returns to the overview and speaks "已保存：<field>". Failure keeps the page open, keeps the draft, and puts the old value back in the profile.
- The page has one mode only. The owner approved on 2026-11-05 that new users go straight to the home page after login (Jayden23018/blind-run-ios#781), so there is no first-setup form any more. Every entry pushes `BlindRunnerProfileView()`.
- An empty nickname no longer blocks saving other rows: the request leaves out `name` (Jayden23018/blind-run-backend#926 makes it optional). The nickname edit page checks 2–50 characters, the same rule as the backend.
- "无偏好" for pace is sent as `NO_PREFERENCE`, and the vision choice page has no "不填" choice, so a spoken "已保存" is always true.
- The vision consent screen, the consent withdrawal behaviour, identifiers and spoken labels stay the same.

## Capabilities

### New Capabilities
- `blind-profile-page`: the overview, and the per-row choice and text edit pages with immediate save.

### Modified Capabilities
- `blind-profile-emergency-entry`: the "Save stays reachable" scenario moves from the profile page (which no longer has a Save button) to the text edit page.

## Impact

- Code: `blindRun/Profile/ProfileModule.swift`, new files in `blindRun/Profile/` for the choice page and the text edit page. The entry points do not change.
- Tests: profile UI tests and accessibility audits that pressed the old Save button; new unit tests for the save-and-revert path.
- API: each change sends the whole profile with `PUT /api/blind/profile`. `name` is left out when empty; this needs Jayden23018/blind-run-backend#926. Before it merges, a user without a nickname gets a 400 when saving other rows.
