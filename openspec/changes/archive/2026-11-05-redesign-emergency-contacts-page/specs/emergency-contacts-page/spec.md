## ADDED Requirements

### Requirement: Adding from Contacts is one tap from the list
The emergency contacts page SHALL offer "从通讯录添加" as the first add row. Tapping it SHALL open the system contact picker directly, without an intermediate form.

#### Scenario: User picks a contact with one phone number
- **WHEN** the user taps "从通讯录添加" and picks a contact
- **THEN** the add form SHALL open with the name and the normalized phone filled in
- **AND** the app SHALL speak and show the name and only the last four digits of the phone

#### Scenario: User cancels the picker
- **WHEN** the user dismisses the picker without a pick
- **THEN** the list SHALL stay unchanged and no form SHALL open

#### Scenario: Contact limit is reached
- **WHEN** five contacts exist
- **THEN** both add rows SHALL be disabled and the page SHALL show and speak the limit reason

### Requirement: Manual entry stays available
The page SHALL offer "手动输入" as the second add row. It SHALL open an empty add form titled "新增紧急联系人".

#### Scenario: User adds a contact by hand
- **WHEN** the user taps "手动输入"
- **THEN** an empty add form SHALL open, and it SHALL still offer a button to pick from Contacts

### Requirement: Relationship is chosen from presets
The form SHALL let the user choose the relationship from a preset list, show a checkmark on the current value, and allow a custom value or no value.

#### Scenario: Stored value matches a preset
- **WHEN** the stored relationship equals a preset
- **THEN** that preset SHALL be checked

#### Scenario: Stored value is custom
- **WHEN** the stored relationship is not a preset
- **THEN** the custom row SHALL show the stored value and be checked

### Requirement: Contact rows keep masked phones and the existing VoiceOver label
Each contact row SHALL show a monogram avatar, the name, the relationship and the masked phone. When exactly one primary contact exists, the list SHALL show it alone in a group titled "主联系人", above a group titled "其他联系人" that holds the other contacts and the add rows, and its avatar SHALL be solid (filled) while the others are tinted. The full phone SHALL NOT appear on the list. The row's accessibility label SHALL stay "姓名，关系X，电话<掩码>，主联系人/非主联系人".

#### Scenario: Primary contact row is read with VoiceOver
- **WHEN** VoiceOver focuses the primary contact row
- **THEN** it SHALL read one element with the name, relationship, masked phone and "主联系人", and the avatar SHALL be hidden from VoiceOver

### Requirement: Form rows are compact
Rows in the add and edit forms SHALL be exactly as tall as the 64pt blind touch target, with no extra vertical inset, and SHALL use the `AppFonts.formRow()` text style. The "设为主联系人" and "删除联系人" actions SHALL share one group.

#### Scenario: Owner reviews the edit form
- **WHEN** the edit form for a non-primary contact is shown at the default text size
- **THEN** each row SHALL be 64pt tall and the two actions SHALL be in the same group
