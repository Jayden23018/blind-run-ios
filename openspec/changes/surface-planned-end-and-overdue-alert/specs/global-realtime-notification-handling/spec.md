## ADDED Requirements

### Requirement: The overdue-run alert outranks routine progress notifications
`ORDER_OVERDUE` means the run has passed its agreed end time and the runner may be unreachable. The app SHALL present it at high priority regardless of the priority the server template assigns, so that it preempts routine dispatch-progress notifications rather than queueing behind them.

#### Scenario: Server sends the overdue alert at normal priority
- **WHEN** an `ORDER_OVERDUE` notification arrives with a server priority of `NORMAL`
- **THEN** the app SHALL treat it as high priority for banner styling, header traits, and speech queue preemption

#### Scenario: Overdue alert is missed while offline
- **WHEN** an `ORDER_OVERDUE` notification is replayed through offline catch-up
- **THEN** the same elevation SHALL apply, because a late alert queued behind progress notifications is later still

#### Scenario: Any other notification arrives
- **WHEN** a notification whose event type is not `ORDER_OVERDUE` arrives
- **THEN** the app SHALL use the priority the server template assigned, so that elevating everything does not make priority meaningless

#### Scenario: The overdue alert competes with the lifecycle suppression gate
- **WHEN** an `ORDER_OVERDUE` notification arrives while the user has an active order
- **THEN** the app SHALL NOT suppress it as a duplicate of an order-status change, because it announces no order status
- **AND** the suppression decision SHALL be driven by event type rather than by matching body text

#### Scenario: The app is not in the foreground
- **WHEN** the app is backgrounded or terminated
- **THEN** client-side elevation SHALL NOT be relied on for delivery, because push fallback is gated on the server template priority rather than on the client's display priority
