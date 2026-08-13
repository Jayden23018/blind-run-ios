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
- **THEN** the screen SHALL read its data from `GET /api/volunteer/achievements`
- **AND** the screen SHALL NOT synthesise recognition tiers that no backend field supplies
- **AND** the screen SHALL show the national star level and the platform badges as two separate sections
- **AND** each badge SHALL be distinguishable by its name and its symbol, not by colour alone

#### Scenario: National star level is shown separately from platform badges
- **WHEN** the recognition screen renders the national star level
- **THEN** the thresholds SHALL be those of GB/T 40143—2021, namely 100, 300, 600, 1000 and 1500 accumulated service hours
- **AND** the screen SHALL NOT merge the star level with the platform badges, because the highest platform hour badge is 50 hours and cannot reach the 100-hour first star
- **AND** the remaining hours to the next star SHALL be available as readable text, not only as the geometry of a progress bar

#### Scenario: Badge list semantics
- **WHEN** the response contains `badges`
- **THEN** the app SHALL treat every entry as unlocked, because the contract states that locked badges do not appear in the list
- **AND** the app SHALL NOT read an `unlocked` flag to decide whether an entry is unlocked
- **AND** an unrecognised badge `code` SHALL still render with its `name` and a fallback symbol rather than failing the whole response

#### Scenario: Progress toward the next badge is not available
- **WHEN** the response omits `nextBadge`
- **THEN** the screen SHALL omit the next-badge progress entirely
- **AND** the screen SHALL NOT derive that progress from client-side badge thresholds

#### Scenario: Achievements request fails or fields are absent
- **WHEN** the request fails, or `totalCompleted` and `totalServiceMinutes` are absent
- **THEN** the screen SHALL treat the missing figures as zero and SHALL NOT fail to render
- **AND** a failed request SHALL offer a retry

#### Scenario: Recognition copy is not a credential
- **WHEN** the recognition screen renders any of its own copy
- **THEN** that copy SHALL NOT use the words 证明, 证书 or 已认证 for service hours or star level, because a verifiable volunteer service record must be issued through the volunteer service information system (民政部令第 67 号) and this platform has no data integration with it
- **AND** the screen SHALL state where an external declaration is actually filed
