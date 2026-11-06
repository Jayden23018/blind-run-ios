## 1. View model

- [x] 1.1 Add `saveChange(savedLabel:revert:)`: validate, save the whole profile, revert and report on failure
- [x] 1.2 Unit tests: success sets "已保存：<label>"; failure reverts the value and keeps the error

## 2. Views

- [x] 2.1 One mode, no parameter (the form mode was dropped after #781 was approved)
- [x] 2.2 Overview: header, grouped cards, group titles, vision group, emergency-contact row
- [x] 2.3 Choice page (64pt rows, check mark, green saved line, footnote)
- [x] 2.4 Text edit page (draft, Save at the bottom, character count for the note)
- [x] 2.5 Empty nickname leaves `name` out; nickname page checks 2–50; pace sends `NO_PREFERENCE`; vision page has no "不填"; withdraw retry row

## 3. Tests and checks

- [x] 3.1 Update UI tests that pressed the old Save button; add choice-save and text-save UI tests
- [x] 3.2 Covering tests and audits are written and compile; not run, by the owner's 2026-11-05 decision ("现在之后的改动，都不要跑测试，我自己来看"). The owner checks on the device.
- [x] 3.3 Device screenshots and visual verdict: not done, same owner decision. The owner checks against the mockup.
- [x] 3.4 Mockup into `docs/ui/mockups/blind-profile-edit-20261105/`, one INDEX row
