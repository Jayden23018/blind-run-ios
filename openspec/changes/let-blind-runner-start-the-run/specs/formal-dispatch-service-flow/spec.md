## MODIFIED Requirements

### Requirement: Service completion is allowed only from IN_PROGRESS
The iOS app SHALL enforce the canonical service path `DRIVER_ARRIVED -> IN_PROGRESS -> COMPLETED`, where either participant explicitly starts service before completion, and SHALL NOT allow `DRIVER_ARRIVED -> COMPLETED` from the client.

#### Scenario: Volunteer starts service after arrival
- **WHEN** a volunteer order is `DRIVER_ARRIVED`
- **THEN** the volunteer service UI SHALL show a "开始跑步" action
- **AND** tapping the action SHALL call `POST /api/orders/{id}/start-service`
- **AND** a successful response SHALL move the order to `IN_PROGRESS`
- **AND** the blind-runner UI SHALL receive `IN_PROGRESS` through WebSocket or polling

#### Scenario: Blind runner starts service after arrival
- **WHEN** a blind-runner order is `DRIVER_ARRIVED`
- **THEN** the blind-runner order page primary action SHALL be "开始跑步"
- **AND** tapping the action SHALL call `POST /api/orders/{id}/start-service` with the blind-runner token
- **AND** a successful response SHALL reload the order so the existing three-second countdown starts from the `DRIVER_ARRIVED -> IN_PROGRESS` transition
- **AND** the app SHALL NOT call `POST /api/orders/{id}/confirm-start` separately, because the backend records the blind runner's consent when the blind runner starts service

#### Scenario: Blind runner starts too early
- **WHEN** the blind runner taps "开始跑步" and the backend returns 409 `SERVICE_START_TOO_EARLY`
- **THEN** the app SHALL show and speak the mapped error copy
- **AND** the app SHALL NOT compute an earliest start time on the client

#### Scenario: The other participant already started
- **WHEN** the blind runner taps "开始跑步" after the volunteer already started service
- **THEN** a successful response or a reload SHALL show the in-service experience without an error

#### Scenario: Volunteer completes service from IN_PROGRESS
- **WHEN** a volunteer order is `IN_PROGRESS`
- **THEN** the volunteer service UI SHALL show a finish service action
- **AND** the action SHALL require second confirmation
- **AND** confirmation SHALL call `POST /api/orders/{id}/finish`
- **AND** the volunteer service UI SHALL also show a cancel action with second confirmation
- **AND** volunteer cancellation SHALL call `POST /api/orders/{id}/cancel`

#### Scenario: Client blocks invalid finish attempt
- **WHEN** code attempts to finish an order whose current status is not `IN_PROGRESS`
- **THEN** the ViewModel action layer SHALL block the request before calling `/api/orders/{id}/finish`
- **AND** the user SHALL receive a clear error or waiting-state message

### Requirement: Mock and tests mirror the formal lifecycle
Mock API behavior and automated tests SHALL mirror the formal dispatch lifecycle used by cloud validation.

#### Scenario: Mock starts service from DRIVER_ARRIVED
- **WHEN** Mock receives `POST /api/orders/{id}/start-service` for an order in `DRIVER_ARRIVED`
- **THEN** Mock SHALL move the order to `IN_PROGRESS`
- **AND** Mock SHALL return success without changing the order when it is already `IN_PROGRESS`, because the backend returns 200 to whichever participant presses second
- **AND** Mock SHALL reject the same endpoint for other order statuses with `INVALID_ORDER_STATUS`

#### Scenario: Mock rejects direct completion from DRIVER_ARRIVED
- **WHEN** Mock receives `POST /api/orders/{id}/finish` for an order in `DRIVER_ARRIVED`
- **THEN** Mock SHALL return an invalid-status error
- **AND** Mock SHALL only allow finish when the order is `IN_PROGRESS`

## ADDED Requirements

### Requirement: Blind-runner arrival copy names the start action
In `DRIVER_ARRIVED`, blind-runner status copy SHALL NOT tell the blind runner to wait for the volunteer to start service. Copy shown on the order page SHALL point to the "开始跑步" action below; copy spoken or shown outside the order page SHALL NOT refer to an on-screen position.

#### Scenario: Order page arrival subtitle
- **WHEN** the blind-runner order page renders `DRIVER_ARRIVED`
- **THEN** the subtitle SHALL include "见面后，轻点下方开始跑步"

#### Scenario: Arrival announcement outside the order page
- **WHEN** the home screen or the voice status query describes `DRIVER_ARRIVED`
- **THEN** the copy SHALL name the "开始跑步" action without referring to an on-screen position
- **AND** the copy SHALL NOT contain "轻点下方" or "等待志愿者开始服务"
- **AND** the copy SHALL stay true when the volunteer page speaks it, so it SHALL NOT claim the volunteer can start without the runner

#### Scenario: Calling the volunteer remains reachable
- **WHEN** the blind-runner order page renders `DRIVER_ARRIVED`
- **THEN** the "遇到问题" row SHALL open the safety hub, which offers calling the volunteer
