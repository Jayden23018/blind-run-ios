## ADDED Requirements

### Requirement: Late cancellation is announced only when the server counts it
When the volunteer cancels an order, the app SHALL decode `CancelOrderResponse` and SHALL say "已记一次临时取消。" only when `countedAsLateCancel` is `true`. The app SHALL NOT compute this on the client and SHALL NOT mention any consequence of the count.

#### Scenario: Counted cancellation
- **WHEN** the volunteer cancels and the response has `countedAsLateCancel: true`
- **THEN** the cancellation announcement SHALL end with "已记一次临时取消。"

#### Scenario: Not counted
- **WHEN** the response has `countedAsLateCancel: false` or omits it
- **THEN** the announcement SHALL NOT mention a late cancellation

#### Scenario: Status push arrives before the cancel response
- **WHEN** the `REMATCHING` status is applied and announced before the cancel response arrives
- **AND** the response then has `countedAsLateCancel: true`
- **THEN** "已记一次临时取消。" SHALL be queued after the announcement already playing, not interrupt it

#### Scenario: One sentence when the order leaves the volunteer
- **WHEN** the volunteer order page or running page applies `REMATCHING` after the volunteer cancelled
- **THEN** exactly one cancellation sentence SHALL be spoken, without a preceding generic status sentence
- **AND** when the home screen's status subscription already spoke the cancellation for the same status, the page SHALL NOT speak it again and SHALL only append "已记一次临时取消。" if the cancellation was counted
- **AND** the cancellation sentence SHALL say "订单已取消，这一单不在你名下了。" and SHALL NOT claim the runner will be rematched

#### Scenario: CANCELLED after the volunteer's own cancellation
- **WHEN** the volunteer's cancel request has succeeded and the order then becomes `CANCELLED` (the rematch limit was reached)
- **THEN** the page SHALL announce the volunteer's cancellation and close like for `REMATCHING`
- **AND** a `CANCELLED` that arrives while the cancel request is still unanswered or its outcome is unknown SHALL be treated as the runner's cancellation

### Requirement: Rule parameters come from the server
The app SHALL read `lateCancelWindowHours` and `volunteerOrderAutoOpenLeadMinutes` from `GET /api/config/rules` and SHALL use them only for display and navigation. When the endpoint fails or returns a missing or non-positive value, the app SHALL fall back to 12 hours and 120 minutes.

#### Scenario: Server window is used in the cancel sheet
- **WHEN** the rules response has `lateCancelWindowHours: 6` and the run starts in 8 hours
- **THEN** the cancel sheet SHALL NOT show the late-cancel notice

#### Scenario: Late-cancel notice states only the count
- **WHEN** the run starts within the window
- **THEN** the cancel sheet notice SHALL say that cancelling now counts once as a late cancellation
- **AND** it SHALL NOT mention any penalty, threshold, or suspension

#### Scenario: Fallback when rules are unavailable
- **WHEN** `GET /api/config/rules` fails
- **THEN** the cancel sheet SHALL use 12 hours and the auto-open lead SHALL be 120 minutes
