# blind-home-idle-state Specification

## Purpose
TBD - created by archiving change redesign-blind-home-idle-state. Update Purpose after archive.
## Requirements
### Requirement: Idle home booking card fills the remaining height

When the blind runner has no active order, the booking entry SHALL be one deep-blue card that fills the height left by the content below it. The card MUST keep the same spoken label, hint and action as the booking block. With an active order the home screen SHALL stay unchanged.

#### Scenario: New runner has nothing below the card

- **WHEN** a verified runner with no run history and no favorite place opens the home screen
- **THEN** the card fills the screen above the tab bar and nothing appears below it

#### Scenario: Largest text size

- **WHEN** the text size is the largest accessibility size
- **THEN** the page scrolls and every row below the card stays reachable

### Requirement: Unverified runner gets an identity entry

When the runner has not passed identity verification, the area below the card SHALL show only an identity verification entry, because booking cannot succeed.

#### Scenario: Unverified runner

- **WHEN** an unverified runner opens the home screen
- **THEN** the identity entry appears, and activating it opens the identity verification page

### Requirement: Run summary block opens the records

A runner with runs in the current month SHALL see that month's run count and distance below the card. Activating the block SHALL open the records tab. When the current month has no runs and earlier runs exist, the block SHALL show the previous month. A runner with no runs SHALL NOT see the block or any empty message. The home screen MUST NOT read the block aloud automatically.

#### Scenario: Runs this month

- **WHEN** the runner has runs this month
- **THEN** the block shows this month's count and distance, and VoiceOver reads one sentence

#### Scenario: First days of a month

- **WHEN** the current month has no runs and the previous month has runs
- **THEN** the block shows the previous month

#### Scenario: Load failure keeps earlier content

- **WHEN** the run data fails to load
- **THEN** the home screen keeps the last known content and does not treat the runner as new

### Requirement: Default start place can be changed

A runner who has run before or has a favorite place SHALL see the default start place below the card. The default SHALL be the current location. The runner SHALL be able to choose a favorite place or add one from this row. The chosen place SHALL become the start place of later bookings, and the app SHALL confirm the change by speech. Telling the booking again by voice MUST keep the chosen place. When location access is denied and no favorite is chosen, the row MUST NOT claim the current location is used.

#### Scenario: Default is the current location

- **WHEN** the runner has not chosen a favorite
- **THEN** the row reads 用当前定位出发

#### Scenario: Favorite becomes the default

- **WHEN** the runner chooses a favorite place
- **THEN** the row shows that place and the next booking starts there

#### Scenario: Favorite added from the row

- **WHEN** the runner adds a favorite place from this row and returns to the home screen
- **THEN** the new place becomes the default

#### Scenario: Spoken fallback names the real start

- **WHEN** a favorite is the start place and the spoken place cannot be found
- **THEN** the app MUST NOT say the current location is used

#### Scenario: Favorite removed

- **WHEN** the chosen favorite is removed
- **THEN** the default returns to the current location

### Requirement: Default start place stays private

The default start place MUST be stored with the same protection as favorite places and MUST NOT be written to `UserDefaults`. It MUST be cleared when the session ends, together with the cached run summary.

#### Scenario: Logout

- **WHEN** the session ends
- **THEN** the default start place and the cached run summary are removed

