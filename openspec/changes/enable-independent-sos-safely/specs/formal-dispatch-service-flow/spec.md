## ADDED Requirements

### Requirement: Approved in-run SOS remains separate from order lifecycle
The iOS app SHALL expose the approved SOS action only to the blind participant of an associated `IN_PROGRESS` order and SHALL keep emergency event lifecycle separate from canonical order status.

#### Scenario: Blind runner triggers during run
- **WHEN** the blind participant successfully triggers SOS for an `IN_PROGRESS` order
- **THEN** emergency state SHALL be associated with that order/event
- **AND** the order SHALL continue to render the backend `IN_PROGRESS` status until a canonical order endpoint changes it

#### Scenario: Volunteer is in the same run
- **WHEN** the accepted volunteer participates in the same `IN_PROGRESS` order
- **THEN** no SOS trigger SHALL be offered to that volunteer
- **AND** the volunteer SHALL still receive the backend's emergency alert as an observer

#### Scenario: Service is not in progress
- **WHEN** order status is not `IN_PROGRESS`
- **THEN** no role SHALL expose the trigger

## MODIFIED Requirements

### Requirement: Cancellation visibility is role-aware
The iOS app SHALL show order cancellation actions according to active role and canonical order status independently from the approved SOS event flow.

#### Scenario: Blind-runner cancellation states
- **WHEN** the active role is `BLIND`
- **THEN** the app SHALL show "取消订单" only for `PENDING_MATCH`, `PENDING_ACCEPT`, and `REMATCHING`
- **AND** confirmation SHALL call the existing cancel endpoint

#### Scenario: Volunteer cancellation states
- **WHEN** the active role is `VOLUNTEER`
- **THEN** the app SHALL show "取消订单" only for `PENDING_ACCEPT`, `DRIVER_EN_ROUTE`, `DRIVER_ARRIVED`, and `IN_PROGRESS`
- **AND** confirmation SHALL call the existing cancel endpoint

#### Scenario: SOS event is active during IN_PROGRESS
- **WHEN** the blind participant has submitted an emergency event
- **THEN** local emergency state SHALL NOT synthesize cancellation, completion, rematching, or another order transition

#### Scenario: Blind runner cannot cancel travel, arrival, or in-service states
- **WHEN** a blind-runner order is `DRIVER_EN_ROUTE`, `DRIVER_ARRIVED`, or `IN_PROGRESS`
- **THEN** the blind-runner screens SHALL NOT show a cancel action
- **AND** the approved `IN_PROGRESS` SOS entry SHALL NOT be presented as, or substituted for, a cancellation action

## REMOVED Requirements

### Requirement: Emergency action is hidden for this release

**Reason**: This dedicated safety change defines and gates the approved dual-role `IN_PROGRESS` flow, exact confirmation, GPS/order payload, backend-confirmed SMS state, failure behavior, accessibility, and acceptance tests.

**Migration**: The blind-runner `IN_PROGRESS` entry replaces the hidden placeholder. The volunteer entry stays hidden and is tracked as a backend routing dependency, not as unfinished iOS work.
