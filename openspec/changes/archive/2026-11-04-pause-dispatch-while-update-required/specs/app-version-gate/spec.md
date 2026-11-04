## ADDED Requirements

### Requirement: A required-update alert pauses volunteer dispatch
When the required-update alert is shown to a volunteer whose dispatch switch is on, the client SHALL turn the switch off through the existing stop-dispatch request and SHALL say so in the alert and aloud. The client SHALL NOT turn the switch back on by itself.

#### Scenario: Switch is on when the alert appears
- **WHEN** the required-update alert appears and the volunteer's dispatch switch is on
- **THEN** the client SHALL send `wantsDispatch=false`
- **AND** on success the switch SHALL show off and the alert SHALL say 「已暂停接单，更新后请重新打开」
- **AND** the same sentence SHALL be spoken

#### Scenario: Stopping dispatch fails
- **WHEN** the stop-dispatch request fails
- **THEN** the switch SHALL stay on
- **AND** the alert SHALL say that dispatch could not be paused, and the same sentence SHALL be spoken
- **AND** the client SHALL NOT retry until the alert appears again

#### Scenario: Switch is already off
- **WHEN** the required-update alert appears and the switch is off
- **THEN** the client SHALL send no request and the alert SHALL NOT claim dispatch was paused

#### Scenario: Optional alert or blind runner
- **WHEN** the dismissible new-version alert appears, or the active role is not volunteer
- **THEN** the dispatch switch SHALL NOT change
