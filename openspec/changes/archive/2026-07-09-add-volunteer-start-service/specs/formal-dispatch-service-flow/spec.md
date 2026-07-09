## MODIFIED Requirements

### Requirement: Service completion is allowed only from IN_PROGRESS
The iOS app SHALL enforce the canonical volunteer-driven service path `DRIVER_ARRIVED -> IN_PROGRESS -> COMPLETED`, where the volunteer explicitly starts service before completion, and SHALL NOT allow `DRIVER_ARRIVED -> COMPLETED` from the client.

#### Scenario: Volunteer starts service after arrival
- **WHEN** a volunteer order is `DRIVER_ARRIVED`
- **THEN** the volunteer service UI SHALL show a "开始服务" action
- **AND** tapping the action SHALL call `POST /api/orders/{id}/start-service`
- **AND** a successful response SHALL move the order to `IN_PROGRESS`
- **AND** the blind-runner UI SHALL receive `IN_PROGRESS` through WebSocket or polling without showing a blind-runner confirmation action

#### Scenario: Volunteer completes service from IN_PROGRESS
- **WHEN** a volunteer order is `IN_PROGRESS`
- **THEN** the volunteer service UI SHALL show a finish service action
- **AND** the action SHALL require second confirmation
- **AND** confirmation SHALL call `POST /api/orders/{id}/finish`

#### Scenario: Client blocks invalid finish attempt
- **WHEN** code attempts to finish an order whose current status is not `IN_PROGRESS`
- **THEN** the ViewModel action layer SHALL block the request before calling `/api/orders/{id}/finish`
- **AND** the user SHALL receive a clear error or waiting-state message

### Requirement: Mock and tests mirror the formal lifecycle
Mock API behavior and automated tests SHALL mirror the formal dispatch lifecycle used by cloud validation.

#### Scenario: Mock starts service from DRIVER_ARRIVED
- **WHEN** Mock receives `POST /api/orders/{id}/start-service` for an order in `DRIVER_ARRIVED`
- **THEN** Mock SHALL move the order to `IN_PROGRESS`
- **AND** Mock SHALL reject the same endpoint for other order statuses with `INVALID_ORDER_STATUS`

#### Scenario: Mock rejects direct completion from DRIVER_ARRIVED
- **WHEN** Mock receives `POST /api/orders/{id}/finish` for an order in `DRIVER_ARRIVED`
- **THEN** Mock SHALL return an invalid-status error
- **AND** Mock SHALL only allow finish when the order is `IN_PROGRESS`
