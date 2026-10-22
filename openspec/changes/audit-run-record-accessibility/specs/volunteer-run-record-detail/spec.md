## ADDED Requirements

### Requirement: Pace colour on the route has a legend and a spoken meaning
When the route is coloured by pace, the map SHALL show a "快 ▬ 慢" legend drawn in the same palette. The legend SHALL NOT be exposed to VoiceOver. The map's spoken description SHALL say what the colours mean and, when there is a fastest full kilometre, which one it was.

#### Scenario: Legend on the map
- **WHEN** the record has pace samples and the route is drawn
- **THEN** the map SHALL show the legend with the text "快" and "慢" at the two ends
- **AND** VoiceOver SHALL NOT stop on it

#### Scenario: Spoken description
- **WHEN** VoiceOver reaches the map description and the record has a fastest split
- **THEN** it SHALL include "颜色表示配速，蓝色快，黄色慢" and "第N公里最快"

#### Scenario: No pace samples
- **WHEN** the record has no pace samples (the route is one colour)
- **THEN** there SHALL be no legend and the description SHALL NOT mention colours

### Requirement: Spoken text carries the prototype's information without mask markers
Everything VoiceOver reads on the volunteer detail SHALL be free of name mask markers (`*`, `＊`). The pace chart and the send button SHALL say what the prototype's `data-vo` says.

#### Scenario: Navigation title
- **WHEN** the runner's name is masked (`陈*`)
- **THEN** the screen SHALL still show "和陈*一起跑"
- **AND** VoiceOver SHALL read "和陈一起跑"

#### Scenario: Pace chart rests
- **WHEN** the record has rests
- **THEN** the chart's spoken summary SHALL include "X 公里处休息" for each rest

#### Scenario: Send button
- **WHEN** VoiceOver reaches the send button
- **THEN** its hint SHALL say "X在这条跑步记录里可以听到这句话"
