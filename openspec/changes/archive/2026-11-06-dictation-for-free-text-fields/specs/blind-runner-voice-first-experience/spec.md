## ADDED Requirements

### Requirement: Free-text fields outside booking offer dictation
The runner message, the review comment, the report detail and the support ticket SHALL each offer a dictation button below the text field. Dictation SHALL use the device speech framework and SHALL NOT send the text to the backend language model.

#### Scenario: Dictating into an empty field
- **WHEN** the field is empty and the user dictates "我穿红色外套"
- **THEN** the field SHALL contain "我穿红色外套"
- **AND** the app SHALL announce "已填入：我穿红色外套"

#### Scenario: Dictating into a field that already has text
- **WHEN** the field contains "东门见" and the user dictates "我穿红色外套"
- **THEN** the field SHALL contain "东门见我穿红色外套"
- **AND** the text typed before recording SHALL NOT be replaced

#### Scenario: Nothing was recognized
- **WHEN** recording ends without recognized text
- **THEN** the field SHALL keep its previous text
- **AND** the app SHALL NOT announce "已填入"

#### Scenario: The user edits the field while recording
- **WHEN** recording is running and the user changes the text in the field
- **THEN** the app SHALL stop recording and SHALL NOT overwrite the user's edit with later recognition results
- **AND** the app SHALL NOT announce "已填入"

#### Scenario: Submitting while recording
- **WHEN** the user submits or saves while recording is running for that field
- **THEN** the app SHALL stop recording before it submits, so the microphone does not keep writing into submitted text

#### Scenario: Keyboard input still works
- **WHEN** speech recognition is not authorized or not available
- **THEN** the text field SHALL still accept keyboard input
