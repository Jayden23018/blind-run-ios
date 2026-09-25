## ADDED Requirements

### Requirement: Invite card shows the runner's escort fields and shared history
The volunteer invite card SHALL show the runner's vision level, tether preference, chat preference, route preference and the number of runs completed together, taken from the dispatch push when present, without inventing values for missing fields.

#### Scenario: Push carries the fields
- **WHEN** a `NEW_ORDER` push carries any of the five fields
- **THEN** the runner row SHALL be built from the push without waiting for `GET /api/orders/available`

#### Scenario: Profile fields are missing or have no preference
- **WHEN** a profile field is absent, or chat or route preference is `NO_PREFERENCE` or unrecognised
- **THEN** that item SHALL NOT be shown, and no default such as "全盲" SHALL be shown in its place

#### Scenario: Runs completed together
- **WHEN** `completedTogetherCount` is 0
- **THEN** the card SHALL say "第一次一起跑"
- **AND** when it is N > 0 the card SHALL say "一起跑过 N 次"
- **AND** when the key is missing no tag SHALL be shown
