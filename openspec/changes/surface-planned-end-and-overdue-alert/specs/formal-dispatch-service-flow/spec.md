## ADDED Requirements

### Requirement: The agreed end time is visible and audible to both parties
Every order carries an agreed end time. The app SHALL surface it to the blind runner and to the volunteer, because the server raises an overdue alert relative to that time and an alert without its reference point cannot be acted on.

#### Scenario: Service is in progress on the blind-runner order screen
- **WHEN** the order status is `IN_PROGRESS` and an agreed end time is present
- **THEN** the status card SHALL show the agreed end time in the first screen
- **AND** the repeat-status announcement SHALL speak it after the status itself
- **AND** the visible text and the spoken text SHALL come from one source rather than being composed twice

#### Scenario: Service has not started or has finished
- **WHEN** the order status is anything other than `IN_PROGRESS`
- **THEN** the status card and the repeat-status announcement SHALL omit the agreed end time, because it is not actionable before the run starts and is not a prediction after it ends

#### Scenario: Volunteer views an order
- **WHEN** the volunteer opens the service card or the order information card
- **THEN** the agreed end time SHALL appear alongside the appointment time

#### Scenario: The agreed end time is absent
- **WHEN** the order carries no agreed end time
- **THEN** the app SHALL omit the row and the spoken clause
- **AND** the app SHALL NOT derive a substitute from the appointment time and the expected duration, because those are independently produced and disagreeing values would place three different end times in front of the same run

### Requirement: Order completion is decided by the server, never by the local clock
The server keeps an order in progress well past its agreed end time before auto-completing it. The app SHALL NOT infer that a run has ended from the agreed end time.

#### Scenario: The agreed end time passes while the order is still in progress
- **WHEN** the current time passes the agreed end time and the server still reports `IN_PROGRESS`
- **THEN** the app SHALL keep reporting location, keep its realtime subscription, and keep the in-progress presentation
- **AND** every end-of-run decision SHALL be driven by the server-reported status
