## ADDED Requirements

### Requirement: Dispatch summary card does not repeat the first screen
The dispatch summary card at the bottom of the volunteer first screen SHALL show only the dispatch status sentence and the coverage radius. It SHALL NOT show completed count, rating, acceptance rate, or dispatched / accepted / declined / timeout counts. Its status sentence SHALL omit the not-available reasons that the to-do section already shows as their own cards (training incomplete, not verified); when every reason is omitted, the card SHALL show only the coverage radius.

#### Scenario: Training is the only reason
- **WHEN** the dispatch summary's only not-available reason is `TRAINING_INCOMPLETE`
- **THEN** the to-do section SHALL show the training card and the dispatch summary card SHALL NOT repeat 「尚未完成必修培训」

#### Scenario: Another reason remains
- **WHEN** the reasons are `TRAINING_INCOMPLETE` and `OFFLINE`
- **THEN** the dispatch summary card SHALL say 「当前未在线」

#### Scenario: No assessment-style figures
- **WHEN** the volunteer scrolls to the dispatch summary card
- **THEN** no acceptance rate and no declined or timeout count SHALL be shown

### Requirement: Star-level card uses one encouraging wording everywhere
Every national star-level card (first screen, service recognition page, escort completion page) SHALL use the same wording. Below the first star it SHALL state the hours remaining to the first star and the accumulated hours, and SHALL NOT say 「尚未达到一星」.

#### Scenario: Volunteer below the first star opens the service recognition page
- **WHEN** a volunteer with 1 accumulated hour and no star opens the service recognition page
- **THEN** the star card SHALL read 「距离一星还差 99 小时」 and its spoken label SHALL NOT contain 「尚未」
