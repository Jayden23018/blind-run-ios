## MODIFIED Requirements

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

### Requirement: Form rows are compact
Rows in the add and edit pages SHALL be exactly as tall as the 64pt blind touch target, with no extra vertical inset, and SHALL use the `AppFonts.formRow()` text style. The "设为主联系人" and "删除联系人" actions SHALL share one group on the edit page. The save action SHALL be a bottom button, not a navigation-bar button; going back SHALL discard unsaved edits.

#### Scenario: Owner reviews the edit form
- **WHEN** the edit page for a non-primary contact is shown at the default text size
- **THEN** each row SHALL be 64pt tall, the two actions SHALL be in the same group, and "保存" SHALL be at the bottom of the page
