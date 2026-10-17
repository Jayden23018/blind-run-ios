## ADDED Requirements

### Requirement: Runner can cancel after the volunteer has arrived, from the server-given time
In the arrived layout (`DRIVER_ARRIVED`, before the run) the runner order page SHALL show a "取消本单" row if and only if the order detail carries a non-null `earliestBlindCancelAt`. Before that time the row SHALL be visible but disabled, and its accessibility label SHALL say the clock time from which cancelling is possible and advise calling the volunteer first. From that time on the row SHALL be enabled and SHALL open the existing cancel confirmation before calling `POST /api/orders/{id}/cancel`. The client SHALL NOT compute the time itself from the arrival time. A value that is present but cannot be parsed SHALL leave the row enabled and let the server decide. `DRIVER_EN_ROUTE` and `IN_PROGRESS` SHALL still offer no cancel entry.

#### Scenario: Server closed the exit
- **WHEN** the order is `DRIVER_ARRIVED` and `earliestBlindCancelAt` is `null` or missing
- **THEN** the page SHALL NOT show the "取消本单" row

#### Scenario: Before the threshold
- **WHEN** now is before `earliestBlindCancelAt` (e.g. 10:10)
- **THEN** the "取消本单" row SHALL be disabled
- **AND** VoiceOver SHALL read "10:10 之后可以取消，先给陪跑员打电话" as part of the row

#### Scenario: At the threshold
- **WHEN** now reaches `earliestBlindCancelAt`
- **THEN** the row SHALL be enabled and tapping it SHALL show the cancel confirmation

#### Scenario: Page stays open across the threshold
- **WHEN** the page is open, the row is disabled, and `earliestBlindCancelAt` passes
- **THEN** the row SHALL become enabled without user action within one polling interval
- **AND** the app SHALL speak once that cancelling is now possible

#### Scenario: Malformed value does not break the order
- **WHEN** `earliestBlindCancelAt` is not a string
- **THEN** the order detail SHALL still decode and the row SHALL NOT be shown

### Requirement: Cancel failures after arrival are read out in the runner's terms
When the runner's cancel request fails with 409 `BLIND_CANCEL_TOO_EARLY`, the app SHALL speak and show the server `message` (it carries the time), falling back to a local sentence only when the message is blank. When it fails with 409 `ORDER_HAS_ACTIVE_EMERGENCY`, the app SHALL say that the order still has an open help request and cannot be cancelled yet, in wording addressed to the runner.

#### Scenario: Clock skew
- **WHEN** the client shows the row enabled but the server answers 409 `BLIND_CANCEL_TOO_EARLY` with message "陪跑员刚到不久，请先打电话联系对方；若一直没碰上，10月10日 10:10之后可以取消"
- **THEN** the app SHALL speak exactly that message and show it on the page
