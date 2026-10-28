## ADDED Requirements

### Requirement: Invite shows the runner's masked name
The volunteer invite card and the invite-state order page SHALL show the runner's masked `blindName` from the dispatch push or the pending-invites list. The screen SHALL keep the mask (for example "李*"); VoiceOver labels SHALL drop the mask characters (for example "跑者李"). When the name is missing, blank, or only mask characters, no name SHALL be shown and none SHALL be invented.

#### Scenario: Push carries a masked name
- **WHEN** a `NEW_ORDER` push has `blindName = "李*"`
- **THEN** the invite card runner row SHALL show "跑者李*" with the avatar initial "李"
- **AND** its VoiceOver label SHALL start with "跑者李" and SHALL NOT contain "*"
- **AND** the invite-state order page SHALL show a runner row with value "李*" and VoiceOver label "跑者李"

#### Scenario: Name is missing
- **WHEN** the push has no `blindName`, or it is blank or only mask characters
- **THEN** the order page SHALL NOT show a runner row
- **AND** the invite card SHALL keep the "跑" avatar placeholder and the label "跑者"
