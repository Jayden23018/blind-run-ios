## ADDED Requirements

### Requirement: Blind runners can hand their run plan to an emergency contact
The blind-runner order experience SHALL offer a way to send the current run plan to an emergency contact through the system message composer, without calling any backend endpoint and without changing order status.

#### Scenario: Run plan is shareable
- **WHEN** the order status is `PENDING_ACCEPT`, `DRIVER_EN_ROUTE`, `DRIVER_ARRIVED`, or `IN_PROGRESS`
- **THEN** the order status screen SHALL present a share-run-plan action
- **AND** the action SHALL prefill the system message composer with the primary emergency contact as recipient
- **AND** the app SHALL NOT issue any network request for this action

#### Scenario: Run plan is not shareable
- **WHEN** the order status is `PENDING_MATCH`, `REMATCHING`, `NO_VOLUNTEER`, `COMPLETED`, or `CANCELLED`
- **THEN** the order status screen SHALL NOT present the share-run-plan action
- **AND** the status decision SHALL be exhaustive over order status rather than membership in a status list

#### Scenario: No emergency contact exists
- **WHEN** the blind runner has no emergency contact and activates the share-run-plan action
- **THEN** the app SHALL route the user to emergency-contact management
- **AND** the app SHALL NOT hide the action, so that its existence remains discoverable without sight

#### Scenario: Device cannot send messages
- **WHEN** `canSendText` reports that the device cannot send messages
- **THEN** the app SHALL state this outcome in visible text and in speech
- **AND** the app SHALL NOT present an empty composer or fail silently

### Requirement: Shared run plan discloses run logistics and nothing else
The shared message SHALL contain only run logistics taken from canonical order detail, and SHALL omit participant contact details and health information.

#### Scenario: Full order detail is available
- **WHEN** the message is composed from an order detail response
- **THEN** the message SHALL include planned start time, start address, planned end time, and order id
- **AND** the message SHALL NOT include `volunteerPhone`, `blindPhone`, `specialNotes`, or `visionLevel`

#### Scenario: Destination is unspecified
- **WHEN** `endAddress` is absent
- **THEN** the message SHALL omit any mention of a destination
- **AND** the message SHALL NOT describe the run as returning to the start address

#### Scenario: A logistics field is absent
- **WHEN** any of planned start time, planned end time, or start address is absent
- **THEN** the message SHALL omit only that item and remain sendable
- **AND** planned end time SHALL come from `plannedEnd` rather than being derived from start time and expected duration

### Requirement: Handoff copy never claims the contact was reached
Because the message composer reports only whether the user pressed send, and the user may edit recipients and body, the app SHALL describe the outcome as handed to the system messaging app and SHALL NOT claim delivery or notification.

#### Scenario: User sends the message
- **WHEN** the composer finishes with a sent result
- **THEN** the app SHALL announce that the message was handed to the system messaging app and ask the user to confirm it there
- **AND** the app SHALL NOT state that the contact was notified, informed, or has received anything

#### Scenario: User cancels or sending fails
- **WHEN** the composer finishes with a cancelled or failed result
- **THEN** the app SHALL announce that nothing was sent
- **AND** the failed case SHALL offer a direct phone call as the alternative

#### Scenario: Composer is dismissed while VoiceOver is active
- **WHEN** the system message composer closes
- **THEN** the app SHALL post the outcome as speech, because the composer runs out of process and its dismissal is not otherwise perceivable without sight
