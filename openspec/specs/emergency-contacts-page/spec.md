# emergency-contacts-page Specification

## Purpose
TBD - created by archiving change redesign-emergency-contacts-page. Update Purpose after archive.
## Requirements
### Requirement: Adding from Contacts is one tap from the list
The emergency contacts page SHALL offer "从通讯录添加" as the first add row. Tapping it SHALL open the system contact picker directly, without an intermediate form. After a pick with a valid mainland mobile number, the app SHALL push one confirmation page instead of a form; that page SHALL be the only step before the contact is saved.

#### Scenario: User picks a contact with one phone number
- **WHEN** the user taps "从通讯录添加" and picks a contact whose normalized phone is a valid 11-digit mainland mobile number
- **THEN** a confirmation page SHALL open that shows the name and only the last four digits of the phone, and the SMS notice for new contacts
- **AND** the page SHALL offer one primary button "添加" at the bottom and a "换一位联系人" row, and SHALL NOT offer relationship or primary-contact inputs
- **AND** tapping "添加" SHALL create the contact with an empty relationship, as primary only when no contact exists yet

#### Scenario: The first contact is added
- **WHEN** the confirmation page opens and the user has no emergency contact yet
- **THEN** the page SHALL show and speak that this person will be the primary contact

#### Scenario: Picked number is not a mobile number
- **WHEN** the picked phone is not a valid 11-digit mainland mobile number
- **THEN** the manual entry page SHALL open with the picked name and number filled in, and the app SHALL speak the reason

#### Scenario: User cancels the picker
- **WHEN** the user dismisses the picker without a pick
- **THEN** the list SHALL stay unchanged and no page SHALL open

#### Scenario: Contact limit is reached
- **WHEN** five contacts exist
- **THEN** both add rows SHALL be disabled and the page SHALL show and speak the limit reason

### Requirement: Manual entry stays available
The page SHALL offer "手动输入" as the second add row. It SHALL push a page with only the name and phone fields, the SMS notice, and a bottom "添加" button. It SHALL NOT offer relationship, primary-contact or pick-from-Contacts controls.

#### Scenario: User adds a contact by hand
- **WHEN** the user taps "手动输入"
- **THEN** a page with exactly two inputs, name and phone, SHALL open
- **AND** tapping "添加" with a missing or invalid field SHALL speak which field is wrong and move focus there, without disabling the button

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
Rows in the add and edit pages SHALL be exactly as tall as the 64pt blind touch target, with no extra vertical inset, and SHALL use the `AppFonts.formRow()` text style. The "设为主联系人" and "删除联系人" actions SHALL share one group on the edit page. The save action SHALL be a bottom button, not a navigation-bar button; going back SHALL discard unsaved edits.

#### Scenario: Owner reviews the edit form
- **WHEN** the edit page for a non-primary contact is shown at the default text size
- **THEN** each row SHALL be 64pt tall, the two actions SHALL be in the same group, and "保存" SHALL be at the bottom of the page

