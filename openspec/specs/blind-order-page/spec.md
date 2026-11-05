# blind-order-page Specification

## Purpose
视障跑者的订单页：跑步前四步（匹配 / 约好 / 出发 / 汇合）与陪跑员订单页 v2 同一套版式，跑步中与已完成在同一页原地变形，底部「求助与安全」每一步都在同一位置。
## Requirements
### Requirement: Runner order page uses the volunteer v2 layout before the run
For the matching, booked, departed and met-up steps, the runner's order page SHALL render a hero card (eyebrow, guide rope, headline or large number, supporting lines), followed by a volunteer card when a volunteer is assigned and an info card. The hero card SHALL be tinted with the order-state colour shared with the volunteer page — booked navy, departed blue, met-up and countdown amber — and its text SHALL use the translucent white tones already verified at ≥4.5:1 on every state colour. While matching (no volunteer assigned) the hero SHALL stay a light card. The hero's visible headline SHALL be part of the same sentence its accessibility label reads. The meeting place SHALL be a tappable v2 place row only when the page can open a map; otherwise it SHALL be a row inside the info card. The page SHALL NOT render the four-segment progress bar.

#### Scenario: Booked order with a start time
- **WHEN** the order is `SCHEDULED_CONFIRMED` or `PENDING_ACCEPT` and has a planned start
- **THEN** the hero SHALL be tinted navy and show the start clock as the large number with unit "开跑" and an eyebrow "已约好 · <day part>"

#### Scenario: Matching order
- **WHEN** the order is `PENDING_MATCH`
- **THEN** the hero SHALL be a light card, its headline SHALL be the existing presentation title, and no volunteer card SHALL be shown

#### Scenario: Volunteer arrived
- **WHEN** the order is `DRIVER_ARRIVED`
- **THEN** the hero SHALL be tinted amber and its text SHALL be white

### Requirement: Guide rope speaks from the runner's perspective
On the runner's page the guide rope's accessibility label SHALL state the step out of four in the runner's words, and the runner's own avatar SHALL read "我".

#### Scenario: Volunteer en route
- **WHEN** the order is `DRIVER_EN_ROUTE`
- **THEN** the rope label SHALL read "第 3 步，共 4 步，陪跑员正在赶来"

### Requirement: Runner page keeps safety entry and in-place running transition
The "求助与安全" button SHALL stay in the bottom action area in every step, and entering `IN_PROGRESS` SHALL transform the same page in place rather than navigate to a new page. While running and after completion, the page SHALL show a tinted hero card (running teal, completed green) holding the side-by-side guide rope and the distance, duration and pace figures. The order page SHALL hide the bottom tab bar in every state, and SHALL therefore show the back button in every state including running and completed, so the page always has an exit.

#### Scenario: Run starts
- **WHEN** the order moves from `DRIVER_ARRIVED` to `IN_PROGRESS`
- **THEN** the hero card SHALL be replaced in place by the teal running hero and the bottom safety button SHALL keep its position

#### Scenario: Leaving during the run
- **WHEN** the order is `IN_PROGRESS` and the runner activates the back button
- **THEN** the app SHALL return to the home tab and the order SHALL keep running

#### Scenario: No tab bar on the order page
- **WHEN** the runner opens the order page in any state
- **THEN** the bottom tab bar SHALL NOT be visible

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

