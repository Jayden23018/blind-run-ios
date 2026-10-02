## ADDED Requirements

### Requirement: Starting the run waits for the runner's consent without disabling the button
When the volunteer presses the start-run button and the server answers `BLIND_CONFIRMATION_PENDING`, the page SHALL show "waiting for the other person to confirm" above the button and SHALL keep the button pressable. When the server answers `SERVICE_START_TOO_EARLY`, the page SHALL speak the time-not-reached message and SHALL NOT compute an earliest time itself.

#### Scenario: Runner has not confirmed yet
- **WHEN** the volunteer presses start-run and the server answers `BLIND_CONFIRMATION_PENDING`
- **THEN** the caption above the button SHALL read "等待对方确认"
- **AND** the button SHALL remain enabled so the volunteer can press it again

#### Scenario: Too early
- **WHEN** the server answers `SERVICE_START_TOO_EARLY`
- **THEN** the page SHALL speak the localized message
- **AND** the "waiting for confirmation" caption SHALL NOT be shown

### Requirement: The runner's consent notification refreshes the arrived page
When the `BLIND_START_CONFIRMED` notification arrives while the current order is in the arrived state, the page SHALL clear the "waiting for confirmation" caption and SHALL re-fetch the order. The notification carries no order id, so it SHALL be ignored when the current order is not in the arrived state.

#### Scenario: Consent arrives while arrived
- **WHEN** `BLIND_START_CONFIRMED` arrives and the order is `DRIVER_ARRIVED`
- **THEN** the caption SHALL return to its normal text and the order SHALL be re-fetched

#### Scenario: Consent arrives on a different state
- **WHEN** `BLIND_START_CONFIRMED` arrives and the order is not `DRIVER_ARRIVED`
- **THEN** nothing SHALL change on the page
