## ADDED Requirements

### Requirement: Volunteer home reads upcoming orders from the dispatch summary
The volunteer home SHALL use `upcomingOrders` from `GET /api/volunteer/dispatch-summary` as the list of accepted orders that have not departed (`PENDING_ACCEPT` and `SCHEDULED_CONFIRMED`). An empty array SHALL mean there are none. A `null` value, or a missing summary, SHALL make the app fall back to `GET /api/orders/mine?role=VOLUNTEER&status=…` for both statuses. These orders SHALL NOT be merged into the active orders and SHALL NOT be registered for live location sharing.

#### Scenario: Summary carries upcoming orders
- **WHEN** the summary has `upcomingOrders` with two orders
- **THEN** the home SHALL list them by planned start time without calling `orders/mine`
- **AND** neither order SHALL become the active order or be registered for location sharing

#### Scenario: Empty array
- **WHEN** `upcomingOrders` is `[]`
- **THEN** the list SHALL be empty and the app SHALL NOT call `orders/mine`

#### Scenario: Null
- **WHEN** `upcomingOrders` is `null`
- **THEN** the app SHALL call `orders/mine` once for each of the two statuses and show what comes back
