## ADDED Requirements

### Requirement: Volunteer actions follow the server-given release times
The volunteer order page SHALL disable a primary action in place until the backend's release time for it has passed, and SHALL state that time above the button and in its accessibility hint. Confirming departure and going en route SHALL use `earliestDepartureAt`; starting the run SHALL use `earliestServiceStartAt`. When the field is absent the action SHALL stay enabled.

#### Scenario: Departure before the release time
- **WHEN** the order is `PENDING_ACCEPT` and `earliestDepartureAt` is in the future
- **THEN** the departure action SHALL be disabled and the caption SHALL read "{H:mm} 起可以按"
- **AND** after that time the action SHALL become enabled without user action

#### Scenario: Confirming from the home scheduled card
- **WHEN** a `SCHEDULED_CONFIRMED` card on the volunteer home is shown and `earliestDepartureAt` is in the future
- **THEN** its "确认我还会去" button SHALL be disabled with the caption "{H:mm} 起可以按"
- **AND** a `PENDING_ACCEPT` card SHALL NOT apply `earliestDepartureAt` to that button

#### Scenario: Waiting for the runner's consent
- **WHEN** the order is `DRIVER_ARRIVED`, the start time has passed, and `blindConfirmDeadlineAt` is in the future
- **THEN** "开始跑步" SHALL stay enabled
- **AND** the caption SHALL say the runner has not pressed start yet and from when the volunteer can start alone

#### Scenario: Fields absent
- **WHEN** the release-time fields are absent
- **THEN** the actions SHALL stay enabled and the backend's 409 copy SHALL remain the fallback
