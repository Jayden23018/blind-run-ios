# volunteer-order-page Specification

## Purpose
陪跑员订单页 v2：用一张随订单状态原地变化的头卡和引导绳，告诉陪跑员几点出发、还有几分钟到、跑者在不在附近，并在每一态都提供位置固定、行为诚实的求助入口。
## Requirements
### Requirement: Order page switches in place by server status
The volunteer order page SHALL render one page whose content switches in place according to the order status returned by `GET /api/orders/{id}`, without pushing a new page. `SCHEDULED_CONFIRMED` and `PENDING_ACCEPT` SHALL render the "agreed" layout, `DRIVER_EN_ROUTE` the "departed" layout, `DRIVER_ARRIVED` the "arrived" layout, `COMPLETED` the completion layout, and a runner-initiated `CANCELLED` the runner-cancelled layout. `IN_PROGRESS` SHALL keep the existing running page.

#### Scenario: Status change keeps the same page
- **WHEN** the order moves from `DRIVER_EN_ROUTE` to `DRIVER_ARRIVED` while the page is open
- **THEN** the page SHALL switch to the arrived layout in place
- **AND** the navigation stack depth SHALL NOT change

#### Scenario: Unknown status does not blank the page
- **WHEN** the backend returns a status value the client does not recognise
- **THEN** the page SHALL still render a navigation bar with the help entry and a readable status line

### Requirement: Agreed layout unlocks the departure action at the server-given time
In the agreed layout the primary action "我出发了" SHALL be enabled only from `primaryActionUnlockAt`. Before that time the page SHALL show the secondary action "我已经出发了" instead. When `suggestedDepartAt`, `departReminderAt`, `primaryActionUnlockAt` and `travelMinutes` are all `null`, the page SHALL show the planned start time and meeting point without inventing a departure time.

#### Scenario: Before unlock
- **WHEN** now is one second before `primaryActionUnlockAt`
- **THEN** the page SHALL show the secondary "我已经出发了" and no yellow primary button

#### Scenario: At unlock
- **WHEN** now reaches `primaryActionUnlockAt` while the page is in the foreground
- **THEN** the button SHALL become the yellow primary "我出发了" without user action

#### Scenario: Departure rejected as too early
- **WHEN** `POST /api/orders/{id}/en-route` returns 409 `DEPARTURE_TOO_EARLY`
- **THEN** the page SHALL show and announce a message saying it is too early to depart and SHALL keep the agreed layout

#### Scenario: No volunteer location yet
- **WHEN** all four departure-time fields are `null`
- **THEN** the page SHALL NOT display a suggested departure time or a reminder time

### Requirement: Departed layout shows server ETA and lateness
In the departed layout the hero number SHALL be `eta.remainingMinutes`, the rope position SHALL follow `eta.progress` clamped to [0.1, 0.85], and the late variant SHALL be used exactly when `eta.late` is true. The late variant SHALL show a non-red notice that the runner has been told about the delay. When `eta` is `null` the page SHALL show that the ETA is not yet available rather than a number.

#### Scenario: On time
- **WHEN** `eta.late` is false and `deltaVsStartMinutes` is -3
- **THEN** the page SHALL say the volunteer arrives 3 minutes early

#### Scenario: Late
- **WHEN** `eta.late` is true
- **THEN** the hero number SHALL use the late colour and a notice SHALL say the runner was told automatically

#### Scenario: ETA update over WebSocket
- **WHEN** an `ORDER_ETA_UPDATED` message for this order arrives
- **THEN** the hero number and rope position SHALL update without refetching the order

### Requirement: Runner presence is shown only when the server says so
The "runner is near the meeting point" pill SHALL appear only when `runnerAtMeetingPoint` is `true`. When it is `false` or `null` the pill SHALL NOT appear and SHALL NOT leave an empty gap.

#### Scenario: Presence unknown
- **WHEN** `runnerAtMeetingPoint` is `null`
- **THEN** no presence pill and no placeholder space SHALL be rendered

### Requirement: Arrived layout uses coarse distance buckets
In the arrived layout the title and subtitle SHALL be derived from `meet.distanceBucket` (`WITHIN_10`, `WITHIN_50`, `WITHIN_100`, `FAR`, `UNKNOWN`). Any unrecognised bucket value SHALL be treated as `UNKNOWN`. The page SHALL NOT display a precise distance in metres. Direction wording SHALL use eight sectors with 5° hysteresis, and spoken direction announcements SHALL be at least 3 seconds apart and only when the wording or bucket changes. When the bucket is `FAR` or `UNKNOWN`, or the device heading is unavailable, the direction sector SHALL be hidden.

#### Scenario: Unrecognised bucket
- **WHEN** the backend sends `distanceBucket = "WITHIN_5"`
- **THEN** the page SHALL render the `UNKNOWN` copy and SHALL NOT fail to decode the order

#### Scenario: Far bucket
- **WHEN** the bucket is `FAR` with `farDistanceKm = 1.8`
- **THEN** the subtitle SHALL say the runner's phone is 1.8 km away and the direction sector SHALL be hidden

#### Scenario: Hysteresis
- **WHEN** the relative bearing oscillates between 21° and 25°
- **THEN** the direction wording SHALL NOT alternate between "前方" and "右前方"

### Requirement: Ring the runner's phone
In the arrived layout the volunteer SHALL be able to call `POST /api/orders/{id}/ring-runner`. The ring button SHALL stay disabled until the returned `ringingUntil`. When `delivered` is false the page SHALL tell the volunteer the runner may not have received it. A 429 response SHALL disable the button for `Retry-After` seconds.

#### Scenario: Ring accepted
- **WHEN** the ring request succeeds with `ringingUntil` 10 seconds later
- **THEN** the button SHALL show "正在响铃…" and SHALL NOT be tappable until `ringingUntil`

#### Scenario: Not delivered
- **WHEN** the response has `delivered = false`
- **THEN** the page SHALL show and announce that the runner may not have received the ring

### Requirement: Quick messages
In the departed and arrived layouts the volunteer SHALL be able to send `POST /api/orders/{id}/quick-message` with code `ALMOST_THERE` or `WAIT_5_MIN`. After a successful send the tapped button SHALL show "已发送" and SHALL NOT send the same code again for 60 seconds. A 429 response SHALL be reported without changing the order state.

#### Scenario: Same code within 60 seconds
- **WHEN** the volunteer taps "我快到了" twice within 60 seconds
- **THEN** only one request SHALL be sent

### Requirement: End waiting after the server-given time
In the arrived layout, from `earliestEndWaitAt` onwards the primary action SHALL change in place from "开始跑步" to "结束等待", calling `POST /api/orders/{id}/end-waiting`. The page SHALL state that ending the wait does not count as the volunteer's cancellation. A 409 `END_WAIT_TOO_EARLY` SHALL keep the "开始跑步" action.

#### Scenario: Before the threshold
- **WHEN** now is one second before `earliestEndWaitAt`
- **THEN** the primary action SHALL be "开始跑步"

#### Scenario: At the threshold
- **WHEN** now reaches `earliestEndWaitAt`
- **THEN** the primary action SHALL be "结束等待"

### Requirement: Completion page shows the shared-run count as sent
The completion layout SHALL show "第 N 次一起跑" with N taken directly from `completedTogetherCount` (not incremented). When N is 1 the copy SHALL say "第一次一起跑". When the field is `null` the relationship title SHALL omit the count. The page SHALL NOT display pace.

#### Scenario: Count as sent
- **WHEN** a completed order has `completedTogetherCount = 4`
- **THEN** the title SHALL say 第 4 次

### Requirement: Help entry on every volunteer order page
Every volunteer order layout SHALL show a "求助" pill at the same position in the top-right of the navigation bar. In `IN_PROGRESS` it SHALL open the existing cloud emergency flow. In every other status it SHALL open a local-call sheet offering 120 and 110, SHALL state that the app will not send a help request on the volunteer's behalf, and SHALL NOT call `POST /api/emergency/trigger`.

#### Scenario: Help before the run
- **WHEN** the volunteer taps "求助" while the order is `DRIVER_ARRIVED`
- **THEN** a local-call sheet SHALL appear with 120 and 110
- **AND** no request SHALL be sent to `POST /api/emergency/trigger`

#### Scenario: Help pill position is stable
- **WHEN** the order changes status while the page is open
- **THEN** the help pill SHALL stay in the same position

### Requirement: Runner identity stays masked
The order page SHALL display the runner's name only as the masked `blindName` sent by the backend and SHALL NOT display a full phone number. Dialling SHALL only pass the number to the system dialler.

#### Scenario: Call the runner
- **WHEN** the volunteer taps "打电话" in the arrived layout
- **THEN** the screen and the VoiceOver label SHALL contain only the masked number

### Requirement: Rope is a single accessible element and motion respects Reduce Motion
The guide rope SHALL be exposed to VoiceOver as one element reading "第 N 步，共 4 步，{状态}" (plus remaining minutes when departed). When Reduce Motion is on, every position, scale and drawing animation on the order page (rope, direction dial, notice bar, primary-button upgrade, completion illustration) SHALL become a fade of at most 0.2 seconds and looping effects SHALL be static. Looping effects SHALL also stop when the app is not active. Colour transitions of the hero card are not motion and SHALL still apply.

#### Scenario: Reduce Motion
- **WHEN** Reduce Motion is enabled and the order becomes `DRIVER_EN_ROUTE`
- **THEN** the volunteer avatar SHALL appear at its new position without sliding and the glow SHALL NOT pulse

#### Scenario: Reduce Motion on arrival
- **WHEN** Reduce Motion is enabled and the order becomes `DRIVER_ARRIVED`
- **THEN** the direction dial SHALL fade in without scaling

### Requirement: Hero card colour follows the order state
The hero card SHALL use a state colour: agreed (`SCHEDULED_CONFIRMED`, `PENDING_ACCEPT`) and runner-cancelled use navy, `DRIVER_EN_ROUTE` uses the departed blue, `DRIVER_ARRIVED` uses the arrived amber, `COMPLETED` uses the done green; the invitation keeps the white card. Text on every state colour SHALL reach 4.5:1. When the state changes while the page is open, the card background SHALL cross-fade over 0.35 seconds. The state colours SHALL NOT be used outside the hero card, except the arrived direction dial, ring button and the emphasised call button after the wait threshold.

#### Scenario: Departing changes the hero colour
- **WHEN** the order moves from `PENDING_ACCEPT` to `DRIVER_EN_ROUTE` while the page is open
- **THEN** the hero card background SHALL change from navy to the departed blue with a 0.35-second transition

#### Scenario: Runner cancels
- **WHEN** the runner cancels the order
- **THEN** the hero card SHALL use navy

