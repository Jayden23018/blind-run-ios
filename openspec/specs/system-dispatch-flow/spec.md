# system-dispatch-flow Specification

## Purpose
TBD - created by archiving change adopt-system-dispatch-flow. Update Purpose after archive.
## Requirements
### Requirement: Volunteer home uses system dispatch summary
The iOS volunteer home screen SHALL use backend dispatch summary data as its primary source of truth and SHALL NOT present a public order pool or volunteer self-selection list as the primary experience.

#### Scenario: Volunteer home loads dispatch summary
- **WHEN** a volunteer opens the home screen
- **THEN** the app SHALL request `GET /api/volunteer/dispatch-summary`
- **AND** the app SHALL render dispatch readiness, not-available reasons, coverage radius, online/location state, active orders, recent orders, and service statistics from the response

#### Scenario: Public order pool is removed from primary home flow
- **WHEN** a volunteer is on the home screen
- **THEN** the app SHALL NOT show "nearby available orders" as the main call to action
- **AND** the app SHALL NOT provide a primary "view all available orders" entry for self-selecting blind-runner appointments

### Requirement: Volunteer availability controls dispatch opt-in
The iOS volunteer availability control SHALL update whether the volunteer wants to receive backend dispatches and SHALL NOT affect an already active accepted order.

#### Scenario: Volunteer turns dispatch on
- **WHEN** an approved volunteer enables the availability switch
- **THEN** the app SHALL update `wantsDispatch` through the backend availability contract
- **AND** the home screen SHALL refresh dispatch summary readiness

#### Scenario: Volunteer turns dispatch off with active order
- **WHEN** a volunteer disables availability while an active order exists
- **THEN** the app SHALL show availability as off for new dispatches
- **AND** the active order entry SHALL remain visible and usable

### Requirement: Volunteer receives timed dispatch prompts
The iOS volunteer client SHALL handle `NEW_ORDER` WebSocket messages as backend dispatch prompts with accept and decline actions only.

#### Scenario: New order dispatch arrives
- **WHEN** `/ws/volunteer` receives a `NEW_ORDER` message
- **THEN** the app SHALL show a 30-second prompt using `dispatchTimeoutSeconds`
- **AND** the prompt SHALL display order time, start address, distance, priority, optional pace, guide dog, notes, and optional start coordinates when present

#### Scenario: Volunteer accepts dispatch
- **WHEN** the volunteer taps accept on a dispatch prompt
- **THEN** the app SHALL report current location if available
- **AND** the app SHALL call `POST /api/orders/{id}/respond` with `action = ACCEPT`
- **AND** the app SHALL navigate to the accepted order detail or service flow on success

#### Scenario: Volunteer declines or times out
- **WHEN** the volunteer taps decline or the prompt timer reaches zero
- **THEN** the app SHALL call `POST /api/orders/{id}/respond` with `action = DECLINE` when appropriate
- **AND** the app SHALL dismiss the prompt without showing a "later" business action

### Requirement: Volunteer statistics and temporary points are displayed
The iOS volunteer home screen SHALL display service statistics from dispatch summary and SHALL use a temporary client-side points placeholder until a real points API exists.

#### Scenario: Summary contains completed count
- **WHEN** dispatch summary contains `totalCompleted`
- **THEN** the app SHALL display completed service count from `totalCompleted`
- **AND** the app SHALL NOT treat `totalAccepted` as completed service count

#### Scenario: Points API is unavailable
- **WHEN** dispatch summary does not contain a real `pointsBalance`
- **THEN** the app SHALL display temporary points as `totalCompleted * 100`
- **AND** recent completed orders without `pointsDelta` SHALL display a temporary `+100` points value

### Requirement: Blind runner waiting describes system dispatch
The iOS blind-runner waiting experience SHALL describe `PENDING_MATCH` as backend system dispatch in progress.

#### Scenario: Blind runner submits appointment
- **WHEN** blind runner order creation succeeds and returns `PENDING_MATCH`
- **THEN** the app SHALL navigate to the order status screen
- **AND** the status text and TTS SHALL say the system is dispatching a suitable volunteer

#### Scenario: Blind runner repeats pending status
- **WHEN** the blind runner taps "重复当前状态" while the order is `PENDING_MATCH`
- **THEN** TTS SHALL replay system-dispatch waiting copy rather than public-order-pool copy

### Requirement: Blind runner state updates remain status driven
The iOS blind-runner order screens SHALL update from WebSocket notifications and REST polling without exposing backend dispatch rounds.

#### Scenario: Volunteer accepts dispatch
- **WHEN** the blind runner receives `ORDER_STATUS_CHANGED` or polling returns `PENDING_ACCEPT`
- **THEN** the app SHALL update the UI to show a volunteer has accepted
- **AND** TTS SHALL announce the accepted volunteer state

#### Scenario: No volunteer is available
- **WHEN** WebSocket or polling returns `NO_VOLUNTEER`
- **THEN** the app SHALL show a no-volunteer terminal state
- **AND** TTS SHALL announce that no volunteer is currently available

#### Scenario: Volunteer location is available
- **WHEN** the order is `DRIVER_EN_ROUTE` or `DRIVER_ARRIVED`
- **THEN** the app SHALL display volunteer location from `VOLUNTEER_LOCATION_UPDATE`
- **AND** the app SHALL use `GET /api/blind/volunteer-location` as a fallback when WebSocket is unavailable

### Requirement: Documentation matches system dispatch
Project documentation SHALL describe backend-controlled dispatch as the primary matching model and SHALL record remaining backend-owned behavior as contract dependencies.

#### Scenario: Documentation is updated
- **WHEN** this change is implemented
- **THEN** product, flow, page, data model, API, architecture, WebSocket, and UI handoff docs SHALL no longer describe public order pool self-selection as the primary volunteer flow
- **AND** docs SHALL state that expansion rings, volunteer ranking, simultaneous last-round dispatch, and citywide fallback notifications are backend-owned

