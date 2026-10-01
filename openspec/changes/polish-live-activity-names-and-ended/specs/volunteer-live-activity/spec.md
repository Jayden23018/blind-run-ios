## MODIFIED Requirements

### Requirement: Lock-screen card uses surname only and neutral wording
The card SHALL show the counterpart only by surname in short labels, SHALL use "跑者" in full sentences, SHALL NOT add "先生" or "女士", and SHALL NOT fall back to the masked name when the surname is unavailable. The departed/arrived card SHALL take the runner surname from `blindSurname`; the volunteer running card SHALL show the runner surname from `blindSurname`; the runner running card SHALL show the volunteer surname from `volunteerSurname`.

#### Scenario: Surname not yet provided by the backend
- **WHEN** the order has `blindName = "李*"` and no surname field
- **THEN** the card SHALL show no name at all

#### Scenario: Surname provided
- **WHEN** the order has `blindSurname = "李"`
- **THEN** the departed/arrived card attributes SHALL carry `runnerSurname = "李"` and the volunteer running card SHALL show "李" as the name

#### Scenario: Runner-side running card
- **WHEN** the runner's order has `volunteerName = "张*"` and `volunteerSurname = "张"`
- **THEN** the card's partner name SHALL be "张"
- **WHEN** only `volunteerName = "张*"` is present
- **THEN** the card SHALL show no partner name

## ADDED Requirements

### Requirement: Ended departure card
When the departed/arrived card's `activityState` is `.ended`, it SHALL render on the `statePaused` background with the headline "引导已结束", SHALL offer no buttons, no guide rope, and no arrival time, and its compact trailing text SHALL read "已结束".

#### Scenario: Backend ends the activity
- **WHEN** the backend pushes `end` and the card is in the `.ended` state with the last content `phase = departed`
- **THEN** the card SHALL NOT show the ETA headline or any action button
