## ADDED Requirements

### Requirement: Completing every mandatory training course is a precondition for receiving dispatches
The system SHALL treat "has passed every currently-active mandatory training course" as a precondition for a volunteer to enter the dispatch candidate pool and to accept an order. This precondition SHALL be independent of, and evaluated separately from, the qualification review (`verified`) and the registration-completion state.

#### Scenario: A volunteer who has not finished mandatory training receives no dispatches
- **WHEN** a volunteer has not passed every active mandatory course
- **THEN** the backend SHALL exclude that volunteer from the dispatch candidate pool
- **AND** an attempt to respond to a dispatch SHALL be rejected with `TRAINING_NOT_COMPLETED`
- **AND** that rejection message SHALL direct the volunteer to training and SHALL NOT ask them to upload qualification documents

#### Scenario: No mandatory course is configured
- **WHEN** no active mandatory course exists
- **THEN** the precondition SHALL be treated as satisfied for every volunteer
- **AND** no volunteer SHALL be excluded from the candidate pool on training grounds

#### Scenario: A mandatory course is deactivated
- **WHEN** an active mandatory course is deactivated
- **THEN** it SHALL no longer count toward the precondition
- **AND** existing progress records for that course SHALL be retained

### Requirement: The app MUST explain the training block and offer a route to resolve it
Whenever the dispatch precondition is unmet because of training, the system SHALL report a structured reason and the app SHALL both state that reason in words and present an actionable route to the training screen in the same place.

#### Scenario: The dispatch summary reports the training reason
- **WHEN** a volunteer has not finished mandatory training
- **THEN** the dispatch summary SHALL include the `TRAINING_INCOMPLETE` reason
- **AND** the app SHALL render it as a specific statement about training
- **AND** the app SHALL NOT fall back to a generic "please retry or update the app" message

#### Scenario: The reason is accompanied by a reachable entry point
- **WHEN** the app displays the training reason on the volunteer home screen
- **THEN** it SHALL present a control that opens the training screen
- **AND** that control SHALL be reachable by a screen reader

#### Scenario: The training reason coexists with the qualification reason
- **WHEN** a volunteer has neither passed qualification review nor finished mandatory training
- **THEN** both reasons SHALL be reported and both SHALL be conveyed to the user

#### Scenario: A permanent entry point exists regardless of the block
- **WHEN** a volunteer has already finished mandatory training
- **THEN** a training entry point SHALL remain available outside the dispatch card
- **AND** it SHALL allow access to optional courses and to review completed ones

### Requirement: Assessment is passed only by answering every question correctly, with unlimited retries
The system SHALL mark a course assessment as passed only when every question is answered correctly. Retries SHALL NOT be limited, throttled, or locked.

#### Scenario: One wrong answer does not pass
- **WHEN** a submission answers all but one question correctly
- **THEN** the assessment SHALL NOT be marked as passed
- **AND** no completion timestamp SHALL be recorded

#### Scenario: A failed submission explains each wrong answer
- **WHEN** a submission is not passed
- **THEN** the response SHALL identify each incorrectly answered question
- **AND** SHALL carry an explanation of the correct handling for it where one is configured
- **AND** SHALL NOT carry the identifier of the correct option

#### Scenario: Retrying preserves answers that were already correct
- **WHEN** the volunteer retries after a failed submission
- **THEN** the app SHALL clear only the selections for incorrectly answered questions

#### Scenario: The answer set must match the question set exactly
- **WHEN** a submission omits a question, repeats a question, or includes a question from another course
- **THEN** the system SHALL reject the submission
- **AND** SHALL NOT grade the subset that could be matched

### Requirement: Correct answers MUST NOT leave the server
The system SHALL NOT include the identifier of a correct option in any client-facing response, in any state, including after the assessment has been passed.

#### Scenario: Course detail carries questions without answers
- **WHEN** the app requests a course detail
- **THEN** the response SHALL carry each question's prompt and its selectable options
- **AND** SHALL NOT carry any indication of which option is correct

#### Scenario: In-process test doubles obey the same rule
- **WHEN** the in-process mock serves a course detail
- **THEN** it SHALL omit the correct option exactly as the real backend does

### Requirement: Study duration MUST be recorded for every course
The system SHALL record accumulated study duration per volunteer per course, because the governing volunteer-training guidance requires training records to include study duration.

#### Scenario: Reported duration accumulates
- **WHEN** the app reports study duration for a course
- **THEN** the reported value SHALL be treated as an increment and added to the stored total

#### Scenario: Reviewing a completed course still accumulates
- **WHEN** the volunteer reports study duration for a course they have already passed
- **THEN** the duration SHALL still be added to the stored total

#### Scenario: Study duration is not a gate
- **WHEN** a volunteer passes an assessment
- **THEN** the system SHALL NOT require any minimum study duration as a condition of passing

#### Scenario: A failed duration report does not interrupt the user
- **WHEN** reporting study duration fails
- **THEN** the app SHALL NOT present an error to the user
- **AND** SHALL record the failure in a diagnosable log

### Requirement: Passing a mandatory course grants no points; passing an optional course grants points once
The system SHALL award points only for the first pass of an optional course, using the point value configured on that course. Mandatory courses SHALL award nothing.

#### Scenario: First pass of an optional course awards its configured points
- **WHEN** a volunteer passes an optional course for the first time
- **THEN** the system SHALL award that course's configured points
- **AND** the resulting ledger entry SHALL be attributed to a training reward

#### Scenario: Passing the same course again awards nothing
- **WHEN** a volunteer passes a course they have already passed
- **THEN** no additional points SHALL be awarded

#### Scenario: Mandatory courses award nothing
- **WHEN** a volunteer passes a mandatory course
- **THEN** no points SHALL be awarded

#### Scenario: The ledger names the training reward
- **WHEN** the points ledger displays a training reward entry
- **THEN** it SHALL be labelled as a training reward and SHALL NOT fall back to a generic "other" label

### Requirement: A training certificate is issued once every mandatory course is passed
The system SHALL issue a certificate identifier once a volunteer has passed every active mandatory course, and SHALL date it by the last mandatory course passed.

#### Scenario: Passing only optional courses issues no certificate
- **WHEN** a volunteer has passed optional courses but not every mandatory one
- **THEN** no certificate identifier SHALL be reported

#### Scenario: The certificate is not reissued on retries
- **WHEN** a volunteer retakes and re-passes a course they had already passed
- **THEN** the recorded completion timestamp and certificate identifier SHALL remain unchanged

### Requirement: Customer support MUST be able to review a volunteer's training record
The system SHALL let an administrator retrieve a volunteer's per-course progress, accumulated study duration, and every assessment attempt, because for volunteers who declined face verification the manual review is the only point at which a human confirms identity.

#### Scenario: The record lists every attempt
- **WHEN** an administrator retrieves a volunteer's training record
- **THEN** it SHALL list each course with its status, study duration, and attempt count
- **AND** SHALL list each attempt with its score, outcome, and per-question selections
- **AND** SHALL NOT include the correct option for any question

#### Scenario: Training completeness does not gate qualification review
- **WHEN** an administrator reviews a volunteer's qualification documents
- **THEN** the training completeness SHALL be shown for information only
- **AND** SHALL NOT prevent approving or rejecting the qualification

### Requirement: Unknown progress states MUST degrade instead of discarding the response
The app SHALL treat the course progress state as an open enumeration.

#### Scenario: An unrecognised state value arrives
- **WHEN** a course carries a progress state the app does not recognise
- **THEN** the app SHALL still render that course and the rest of the response
- **AND** SHALL NOT present the raw value or internal terminology to the user
- **AND** SHALL NOT treat the course as completed

#### Scenario: The completion flag is absent
- **WHEN** the response omits the mandatory-completion flag
- **THEN** the app SHALL treat mandatory training as unfinished
