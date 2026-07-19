## MODIFIED Requirements

### Requirement: Blind runner state updates remain status driven
The blind-runner order experience SHALL remain driven by canonical order status while presenting the associated volunteer's fresh live location during eligible states and the completed run summary after `COMPLETED`.

#### Scenario: Volunteer is travelling, arrived, or running
- **WHEN** the order is `DRIVER_EN_ROUTE`, `DRIVER_ARRIVED`, or `IN_PROGRESS`
- **THEN** the blind-runner flow MAY present the associated volunteer's fresh map marker from routed WebSocket data
- **AND** it SHALL keep status, primary action, and repeat-status information accessible ahead of auxiliary map inspection

#### Scenario: Order completes
- **WHEN** canonical order detail becomes `COMPLETED`
- **THEN** the blind-runner completion flow SHALL offer the track summary with blind route, distance, duration, and pace

### Requirement: Volunteer service flow presents associated blind-runner location
The volunteer service flow SHALL present the associated blind runner's fresh location during `DRIVER_EN_ROUTE`, `DRIVER_ARRIVED`, and `IN_PROGRESS` without changing lifecycle actions.

#### Scenario: Blind-runner location is fresh
- **WHEN** a matching `BLIND_LOCATION_UPDATE` is routed during an eligible order state
- **THEN** the volunteer map SHALL update the blind-runner marker
- **AND** en-route, arrived, start-service, finish, and cancel permissions SHALL remain based only on canonical order status

### Requirement: Service completion remains separate from track availability
`POST /api/orders/{id}/finish` SHALL remain the only volunteer action that moves `IN_PROGRESS` to `COMPLETED`; track fetching and summary rendering SHALL NOT alter that transition.

#### Scenario: Track endpoint is temporarily unavailable after finish
- **WHEN** order completion succeeds but track loading fails or is delayed
- **THEN** the order SHALL remain `COMPLETED`
- **AND** the summary SHALL show retry/unavailable state without retrying finish
