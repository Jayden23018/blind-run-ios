## MODIFIED Requirements

### Requirement: The booking form shows the profile default pace with its source
When the runner has not picked a pace for this run and the profile has a default pace, the booking review items (read back by voice booking) SHALL include that default and SHALL say it comes from the profile. The create-order request SHALL still omit the pace, so the backend fallback stays the only source of the effective value.

#### Scenario: Profile has a default pace and none is picked
- **WHEN** the profile default pace is "EASY" and the runner has not picked a pace
- **THEN** the review list SHALL include "配速偏好" with the value "轻松，资料里的默认"
- **AND** the create-order request SHALL NOT carry `pacePreference`

#### Scenario: The runner picks a pace
- **WHEN** the pace for this run is "MODERATE"
- **THEN** the review list SHALL show "中等" without the profile label
- **AND** the create-order request SHALL carry `MODERATE`

#### Scenario: The profile has no default pace
- **WHEN** the profile has no default pace and the runner has not picked one
- **THEN** the unset option SHALL keep the title "无偏好"
- **AND** the review list SHALL NOT include a pace item

#### Scenario: Voice read-back
- **WHEN** the voice wizard reads the order back and the utterance did not mention pace
- **THEN** the read-back SHALL NOT name the profile default pace
