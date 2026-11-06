## MODIFIED Requirements

### Requirement: Overview on every entry
The profile page SHALL show a checklist of cards from every entry, grouped into "未设置" and "已设置".

#### Scenario: Open from the account page
- **WHEN** the runner opens "个人资料" from the account page
- **THEN** the page shows the nickname with a "修改昵称" link and five cards: "陪跑方式", "视力状况与导盲犬", "途中提示", "其他需求", "紧急联系人"
- **AND** each card shows its status line and who can see it
- **AND** the page has no bottom Save button

#### Scenario: Emergency-contact row
- **WHEN** the runner taps the emergency-contact card
- **THEN** `EmergencyContactsView` opens

### Requirement: Vision consent stays separate
The vision card SHALL ask for the separate consent before any vision question, and SHALL keep the withdrawal behaviour.

#### Scenario: No consent yet
- **WHEN** the runner opens the vision card without consent
- **THEN** the first screen is the consent screen, with the title, all disclosures and both buttons taken word for word from the existing vision consent
- **AND** the two buttons have the same size

#### Scenario: Decline
- **WHEN** the runner presses "不填这一项"
- **THEN** the app saves at once with both fields as `NOT_SPECIFIED`, closes the sheet, and shows and speaks the existing decline feedback

#### Scenario: Withdraw
- **WHEN** the runner has consented and taps "撤回同意" on the vision card
- **THEN** the app saves at once with both fields as `NOT_SPECIFIED`, as before

### Requirement: Spoken "saved" is true
The app SHALL NOT say "已保存" for a choice that the request does not send.

#### Scenario: No pace preference
- **WHEN** the runner picks "无偏好" for pace
- **THEN** the request carries `defaultPace: NO_PREFERENCE`

#### Scenario: Withdraw not saved
- **WHEN** the consent withdrawal fails
- **THEN** the withdraw action stays on the vision card so the runner can try again

## ADDED Requirements

### Requirement: One question per screen, saved per card
Each card except the emergency-contact card SHALL open a sheet that shows one question per screen and saves the whole card once.

#### Scenario: Continue needs an answer
- **WHEN** a single-choice question has no answer
- **THEN** "继续" is disabled and VoiceOver hears the hint "请先选择一项"

#### Scenario: Focus moves to the question
- **WHEN** the runner moves to the next or previous question
- **THEN** VoiceOver focus moves to the question title

#### Scenario: Card saved
- **WHEN** the runner presses "完成" on the last question and the save succeeds
- **THEN** the app sends `PUT /api/blind/profile` with the whole profile, closes the sheet, moves VoiceOver focus to that card, and shows and speaks "已保存：<summary>"

#### Scenario: Card not saved
- **WHEN** the save fails
- **THEN** the sheet stays on the last question with all answers, the error is shown and spoken, and the profile keeps the old values

#### Scenario: Close without finishing
- **WHEN** the runner closes the sheet after changing an answer
- **THEN** the app asks "放弃本次修改？" and saves nothing if the runner confirms

### Requirement: Common phrases replace free text
The 途中提示 and 其他需求 cards SHALL store chosen phrases and the supplement line in `guidePreferenceText` and `specialNeeds`, joined with "；".

#### Scenario: Read back stored text
- **WHEN** the stored text contains known phrases and other text
- **THEN** the known phrases are pre-selected and the other text appears unchanged in the supplement line

#### Scenario: Too long
- **WHEN** the joined text is longer than 80 characters (途中提示) or 500 characters (其他需求)
- **THEN** "完成" does not save, and the app shows and speaks how many characters are over

#### Scenario: No other needs
- **WHEN** the runner picks "无其他需求"
- **THEN** all other phrases on that question are cleared
- **AND** picking any other phrase clears "无其他需求"

### Requirement: Nickname edit page
The nickname SHALL keep its edit page with a Save button.

#### Scenario: Nickname not saved
- **WHEN** the nickname is not 2–50 characters or the save fails
- **THEN** the edit page stays open with the draft, the error is spoken and shown, and the profile keeps the old value

## REMOVED Requirements

### Requirement: Option rows save at once
**Reason**: Replaced by cards with one question per screen, saved per card.
**Migration**: Use the card flow. See "One question per screen, saved per card".

### Requirement: Text rows save from an edit page
**Reason**: Note and special needs become common phrases. Only the nickname keeps an edit page.
**Migration**: See "Common phrases replace free text" and "Nickname edit page".
