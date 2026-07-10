## ADDED Requirements

### Requirement: Blind-runner identity approval is mandatory for booking
The iOS app SHALL require backend-approved blind-runner identity verification before enabling booking or sending `POST /api/orders`.

#### Scenario: Verified blind runner reaches booking
- **WHEN** the blind-runner basic profile is complete, identity status is approved, at least one emergency contact exists, exactly one contact is primary, and all location/time gates pass
- **THEN** the app SHALL enable the existing booking submission flow

#### Scenario: Identity is incomplete or rejected
- **WHEN** identity status is missing, pending, or rejected
- **THEN** the app SHALL block booking without sending `POST /api/orders`
- **AND** the app SHALL show and speak the current verification status and next action

### Requirement: Blind runners can submit identity verification privately
The iOS app SHALL submit identity name and number only to `POST /api/blind/verify-identity` and SHALL treat backend verification status as authoritative.

#### Scenario: Identity submission is approved
- **WHEN** the user submits valid identity data and the backend reports approval
- **THEN** the app SHALL clear the entered identity-card number from memory
- **AND** the app SHALL update and announce the approved status

#### Scenario: Identity submission is pending
- **WHEN** the backend reports a pending verification state
- **THEN** the app SHALL keep booking blocked
- **AND** the app SHALL refresh status according to the documented contract without resubmitting identity data automatically

#### Scenario: Identity submission is rejected
- **WHEN** the backend rejects the verification
- **THEN** the app SHALL clear the entered identity-card number
- **AND** the app SHALL present a safe rejection reason and retry action without reading the full identity number aloud

### Requirement: Identity-card data is not persisted or exposed
The iOS app MUST keep the full identity-card number out of persistent storage, global app state, logs, analytics, TTS output, post-submission accessibility values, and test screenshots.

#### Scenario: User leaves identity entry
- **WHEN** the identity screen disappears or the app enters the background
- **THEN** the in-memory identity-card number SHALL be cleared

#### Scenario: Verification error is announced
- **WHEN** identity submission fails
- **THEN** the error and VoiceOver announcement SHALL NOT contain the submitted identity-card number

### Requirement: Blind runners can manage one to five emergency contacts
The iOS app SHALL provide an accessible list that supports create, edit, delete, and set-primary operations for one to five emergency contacts.

#### Scenario: User adds contacts below the limit
- **WHEN** fewer than five contacts exist and the user submits a valid new contact
- **THEN** the app SHALL call the contact-create endpoint and refresh the complete server list

#### Scenario: User reaches the contact limit
- **WHEN** five contacts exist
- **THEN** the app SHALL disable adding another contact
- **AND** it SHALL explain and speak the five-contact limit

#### Scenario: User edits a masked contact without changing the phone
- **WHEN** an existing masked phone value is left unchanged
- **THEN** the app SHALL omit the unchanged phone from the update request
- **AND** it SHALL preserve the server-stored phone

### Requirement: Emergency contacts preserve a primary-contact invariant
The iOS app SHALL require at least one contact and exactly one primary contact before booking.

#### Scenario: User sets a different primary contact
- **WHEN** the user confirms “设为主联系人” on a non-primary contact
- **THEN** the app SHALL call the set-primary endpoint and refresh the complete list
- **AND** exactly one contact SHALL be presented as primary

#### Scenario: User attempts to delete the final contact
- **WHEN** only one emergency contact remains
- **THEN** the app SHALL block deletion and explain that one contact is required

#### Scenario: User attempts to delete the primary contact
- **WHEN** multiple contacts exist and the user tries to delete the primary contact
- **THEN** the app SHALL require another contact to be made primary first

### Requirement: Identity and contact management are voice-first and accessible
Identity and emergency-contact screens SHALL expose meaningful VoiceOver order, labels, hints, validation, loading states, destructive confirmations, and concise repeatable TTS status.

#### Scenario: Contact list is read with VoiceOver
- **WHEN** assistive technology focuses a contact row
- **THEN** it SHALL announce name, relationship when available, masked phone, primary state, and available actions without exposing hidden sensitive data

#### Scenario: Contact mutation succeeds
- **WHEN** add, edit, delete, or set-primary succeeds
- **THEN** the app SHALL announce the result and the resulting contact count or primary contact
