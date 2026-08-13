## MODIFIED Requirements

### Requirement: Volunteer statistics and service recognition are displayed
The iOS volunteer home screen SHALL display service statistics from dispatch summary, and SHALL derive every displayed figure from a backend-provided field. The app SHALL NOT synthesise a currency, balance, or reward figure that no backend field supplies.

#### Scenario: Summary contains completed count
- **WHEN** dispatch summary contains `totalCompleted`
- **THEN** the app SHALL display completed service count from `totalCompleted`
- **AND** the app SHALL NOT treat `totalAccepted` as completed service count

#### Scenario: A reward field is absent
- **WHEN** dispatch summary omits a rewards figure such as `pointsBalance`, or a recent order omits `pointsDelta`
- **THEN** the app SHALL omit that figure entirely
- **AND** the app SHALL NOT substitute a value derived from `totalCompleted`
- **AND** the app SHALL NOT present a rewards catalogue, balance, or redemption path that no backend endpoint serves

#### Scenario: Volunteer opens service recognition
- **WHEN** the volunteer opens the service recognition screen
- **THEN** the screen SHALL show tiers keyed to completed service count with the unlock threshold of each tier stated
- **AND** each tier SHALL be distinguishable by its name and its symbol, not by colour alone
- **AND** a locked tier SHALL state how many further completed services unlock it
- **AND** the screen SHALL read its data from the already-loaded dispatch summary without issuing its own request

#### Scenario: Completed count is absent
- **WHEN** `totalCompleted` is absent from dispatch summary
- **THEN** the recognition screen SHALL treat the count as zero and show every tier as locked
- **AND** the screen SHALL NOT fail to render
