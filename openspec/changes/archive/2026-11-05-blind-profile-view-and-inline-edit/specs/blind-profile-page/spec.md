## Purpose

Lets the blind runner see the whole profile first and change one row at a time, with each change saved at once.

## ADDED Requirements

### Requirement: Overview on every entry
The profile page SHALL show the profile read-only, grouped by when a volunteer can see each field, from every entry.

#### Scenario: Open from the account page
- **WHEN** the runner opens "个人资料" from the account page
- **THEN** the page shows the nickname, a group titled "派单时，陪跑员就会看到" with guidance and default pace, a group titled "接单后，陪跑员才看到" with the note to the volunteer and special needs, the vision group, and one emergency-contact row
- **AND** the page has no bottom Save button

#### Scenario: Emergency-contact row
- **WHEN** the runner taps the emergency-contact row
- **THEN** `EmergencyContactsView` opens

### Requirement: Option rows save at once
Guidance, default pace, vision and guide dog SHALL open a choice page where one tap saves the whole profile.

#### Scenario: Choice saved
- **WHEN** the runner taps a choice that differs from the current value
- **THEN** the app sends `PUT /api/blind/profile` with the whole profile
- **AND** on success the check mark is on the new choice and the app shows and speaks "已保存：<choice>"

#### Scenario: Choice not saved
- **WHEN** the save fails
- **THEN** the app speaks and shows the error, and the check mark goes back to the old value

### Requirement: Text rows save from an edit page
Nickname, note to the volunteer and special needs SHALL open an edit page with a Save button.

#### Scenario: Text saved
- **WHEN** the runner presses Save and the save succeeds
- **THEN** the app returns to the overview, the row shows the new text, and the app speaks "已保存：<field>"

#### Scenario: Text not saved
- **WHEN** the save fails or validation fails (nickname not 2–50 characters, note longer than 80 characters)
- **THEN** the edit page stays open with the draft, the error is spoken and shown, and the profile keeps the old value

### Requirement: Vision consent stays separate
The vision group SHALL keep the separate consent and the withdrawal behaviour.

#### Scenario: No consent yet
- **WHEN** the runner has not agreed to the vision consent
- **THEN** the vision group has only the row "填写视力状况", and tapping it opens the consent screen first

#### Scenario: Withdraw
- **WHEN** the runner taps "撤回这两项的同意"
- **THEN** the app saves at once with both fields as `NOT_SPECIFIED`, as before

### Requirement: Empty nickname does not block other rows
A save from any row other than the nickname SHALL leave `name` out of the request when the nickname is empty.

#### Scenario: New user without a nickname
- **WHEN** the runner has no nickname and changes the guidance
- **THEN** the request has no `name` key and the guidance is saved

### Requirement: Spoken "saved" is true
The app SHALL NOT say "已保存" for a choice that the request does not send.

#### Scenario: No pace preference
- **WHEN** the runner picks "无偏好" for pace
- **THEN** the request carries `defaultPace: NO_PREFERENCE`

#### Scenario: Withdraw not saved
- **WHEN** the consent withdrawal fails
- **THEN** the withdraw row stays in the vision group so the runner can try again
