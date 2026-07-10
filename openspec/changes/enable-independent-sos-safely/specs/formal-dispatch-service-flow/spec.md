## ADDED Requirements

### Requirement: Approved independent SOS remains separate from order lifecycle
The iOS app SHALL expose the approved blind-runner SOS flow with or without an eligible active order and SHALL keep the emergency event lifecycle separate from canonical order status.

#### Scenario: SOS is triggered during active service
- **WHEN** a blind runner triggers SOS for an order in `DRIVER_EN_ROUTE`, `DRIVER_ARRIVED`, or `IN_PROGRESS`
- **THEN** the app SHALL associate the order ID with the emergency request
- **AND** it SHALL continue to render the backend order status without synthesizing an emergency status

#### Scenario: Independent SOS is triggered
- **WHEN** a blind runner triggers SOS without an eligible active order
- **THEN** the app SHALL omit the order ID and track the returned emergency event independently

## MODIFIED Requirements

### Requirement: Cancellation visibility is role-aware
The iOS app SHALL show order cancellation actions according to both the active role and the order status, while continuing to use the existing cancel endpoint. Cancellation availability SHALL remain independent from the approved SOS event flow.

#### Scenario: Blind-runner cancellation states
- **WHEN** the active role is `BLIND`
- **THEN** the app SHALL show "取消订单" only for `PENDING_MATCH`, `PENDING_ACCEPT`, and `REMATCHING`
- **AND** the action SHALL require second confirmation
- **AND** confirmation SHALL call `POST /api/orders/{id}/cancel`

#### Scenario: Volunteer cancellation states
- **WHEN** the active role is `VOLUNTEER`
- **THEN** the app SHALL show "取消订单" only for `PENDING_ACCEPT`, `DRIVER_EN_ROUTE`, `DRIVER_ARRIVED`, and `IN_PROGRESS`
- **AND** the action SHALL require second confirmation
- **AND** confirmation SHALL call `POST /api/orders/{id}/cancel`
- **AND** successful volunteer cancellation SHALL move the backend order to `REMATCHING`
- **AND** after a successful cancellation response the volunteer UI SHALL clear the local active service screen instead of fetching the order with a token that may no longer be a participant

#### Scenario: Blind runner cannot cancel travel, arrival, or in-service states
- **WHEN** a blind-runner order is `DRIVER_EN_ROUTE`, `DRIVER_ARRIVED`, or `IN_PROGRESS`
- **THEN** the blind-runner screens SHALL NOT show a cancel action
- **AND** the approved SOS action SHALL remain separately available according to `independent-sos-safety` without changing cancellation permissions or canonical order status

## REMOVED Requirements

### Requirement: Emergency action is hidden for this release

**Reason**: The dedicated `enable-independent-sos-safely` change formally introduces the GPS, notification, failure, compliance, accessibility, cooldown, and acceptance requirements previously required before emergency UI could be enabled.

**Migration**: Replace hidden/deferred emergency affordances with the approved independent SOS event flow only after all tasks and release gates in this change are complete.
