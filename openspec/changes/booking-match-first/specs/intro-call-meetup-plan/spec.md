## ADDED Requirements

### Requirement: Meetup plan on a time-flexible order fixes the exact time and the running needs
On a time-flexible order, the volunteer's meetup plan SHALL require an exact start time and SHALL offer pace, guide dog and notes, prefilled from the runner's profile and the runner's preferred time.

#### Scenario: Volunteer submits without an exact time
- **WHEN** the volunteer submits a plan for a time-flexible order without a start time
- **THEN** the app SHALL NOT send the plan and SHALL say that the start time must be agreed first

#### Scenario: Runner hears the needs before confirming
- **WHEN** the runner reviews a plan that carries pace, guide dog or notes
- **THEN** those items SHALL be read in the fixed plan order after the meeting details
- **AND** an item the volunteer changed SHALL be announced together with its previous value
