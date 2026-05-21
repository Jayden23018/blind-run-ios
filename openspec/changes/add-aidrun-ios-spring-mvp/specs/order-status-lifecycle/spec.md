## ADDED Requirements

### Requirement: Order normal lifecycle is fixed

The system MUST support only the normal lifecycle `matching -> accepted -> arrived -> in_progress -> completed`.

#### Scenario: Happy path lifecycle
- **WHEN** a matching order is accepted, the volunteer arrives, the blind runner confirms start, and the volunteer completes service
- **THEN** the order status changes through `accepted`, `arrived`, `in_progress`, and `completed`

### Requirement: Only matching orders can be accepted

The system MUST allow volunteers to accept only orders whose status is `matching`.

#### Scenario: Concurrent accept loses race
- **WHEN** a second volunteer attempts to accept an order already changed from `matching` to `accepted`
- **THEN** the backend returns `ORDER_ALREADY_ACCEPTED`

### Requirement: Invalid transitions are rejected

The system MUST reject lifecycle operations that do not match the current order status.

#### Scenario: Complete before start
- **WHEN** a volunteer attempts to complete an order that is not `in_progress`
- **THEN** the backend returns `INVALID_ORDER_STATUS`

#### Scenario: Emergency is terminal for MVP lifecycle actions
- **WHEN** an order is in `emergency`
- **THEN** arrive, confirm-start, complete, and cancel actions are rejected with `INVALID_ORDER_STATUS`

### Requirement: Cancellation is allowed only before service starts

The system MUST allow blind runners or volunteers to cancel only `matching`, `accepted`, or `arrived` orders and record fixed cancellation reason data.

#### Scenario: Cancel in progress blocked
- **WHEN** a user attempts ordinary cancellation for an `in_progress` order
- **THEN** the backend returns `INVALID_ORDER_STATUS`

### Requirement: Blind runner polls active order status

The iOS app MUST poll order details every 5 seconds on blind runner waiting and active service pages.

#### Scenario: Volunteer accepted during polling
- **WHEN** a volunteer accepts a blind runner's `matching` order
- **THEN** the blind runner app observes the updated `accepted` state within the next polling interval

### Requirement: Rating is optional after completion

The system MUST allow, but not require, the blind runner to submit a star rating after an order is completed.

#### Scenario: Completed order without rating
- **WHEN** an order reaches `completed` and the blind runner does not rate
- **THEN** the order remains completed and the demo flow is still valid
