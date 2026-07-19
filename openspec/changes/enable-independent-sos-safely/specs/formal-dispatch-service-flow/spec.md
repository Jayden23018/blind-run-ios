## ADDED Requirements

### Requirement: Approved in-run SOS remains separate from order lifecycle
The iOS app SHALL expose the approved dual-role SOS action only for associated `IN_PROGRESS` participants and SHALL keep emergency event lifecycle separate from canonical order status.

#### Scenario: Blind runner triggers during run
- **WHEN** the blind participant successfully triggers SOS for an `IN_PROGRESS` order
- **THEN** emergency state SHALL be associated with that order/event
- **AND** the order SHALL continue to render the backend `IN_PROGRESS` status until a canonical order endpoint changes it

#### Scenario: Volunteer triggers during run
- **WHEN** the accepted volunteer successfully triggers SOS for the same `IN_PROGRESS` order
- **THEN** equivalent event separation and status-neutral behavior SHALL apply

#### Scenario: Service is not in progress
- **WHEN** order status is not `IN_PROGRESS`
- **THEN** neither role SHALL expose the trigger

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
- **WHEN** either participant has submitted an emergency event
- **THEN** local emergency state SHALL NOT synthesize cancellation, completion, rematching, or another order transition

## REMOVED Requirements

### Requirement: Emergency action is hidden for this release

**Reason**: This dedicated safety change defines and gates the approved dual-role `IN_PROGRESS` flow, exact confirmation, GPS/order payload, backend-confirmed SMS state, failure behavior, accessibility, and acceptance tests.

**Migration**: Replace hidden placeholders only after all contract, product/safety, dependency, and release-validation tasks in this change are complete.
