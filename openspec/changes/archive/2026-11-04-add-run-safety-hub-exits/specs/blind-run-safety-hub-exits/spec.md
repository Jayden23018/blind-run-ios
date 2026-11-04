## ADDED Requirements

### Requirement: Runner can end the run when the volunteer is unreachable
While the order is `IN_PROGRESS` and the session is valid, the runner's safety hub SHALL offer "陪跑员联系不上，结束本次陪跑". Activating it SHALL ask for confirmation first. After confirmation the hub SHALL close and the client SHALL call `POST /api/orders/{id}/finish`. The client SHALL NOT decide by itself whether the volunteer is offline. In any other state, or when the session has expired, the hub SHALL NOT show this action.

#### Scenario: Volunteer still online
- **WHEN** the runner confirms and the server answers 409 `VOLUNTEER_STILL_ONLINE` with a message
- **THEN** the client SHALL show and speak that message unchanged
- **AND** the order SHALL stay `IN_PROGRESS`

#### Scenario: Volunteer offline long enough
- **WHEN** the runner confirms and the server answers 200
- **THEN** the order page SHALL move to the finished state
- **AND** the completion sentence SHALL say that the runner ended the run, not that the volunteer did

#### Scenario: Not running
- **WHEN** the runner opens the safety hub in `DRIVER_ARRIVED`
- **THEN** the hub SHALL NOT show the end-run action

### Requirement: Safety hub explains what to do when the volunteer is unwell
While the order is `IN_PROGRESS`, the safety hub SHALL show a fixed guidance block titled "陪跑员身体不适或倒地怎么办" that tells the runner to call 120 first, then use "播报我的位置", then contact the emergency contact. VoiceOver SHALL read the block as one element.

#### Scenario: Guidance during the run
- **WHEN** the runner opens the safety hub during `IN_PROGRESS`
- **THEN** the guidance block SHALL be present after the tiles

### Requirement: Overdue alert matches the runner's real options
When the runner's app receives `ORDER_OVERDUE`, the banner and the speech SHALL use a local sentence that asks the volunteer to end the run if all is well, says the runner can end it from the safety hub when the volunteer cannot be reached, and says to use help when in danger. The volunteer's app SHALL keep the server text.

#### Scenario: Runner receives the overdue alert
- **WHEN** a runner session receives `ORDER_OVERDUE`
- **THEN** the spoken text SHALL NOT say "让志愿者点击结束服务"

### Requirement: Run start reminds the runner about system Emergency SOS
When the run-start countdown finishes, after "开始跑步" is spoken, the client SHALL speak one reminder that iPhone Emergency SOS can be started by holding the side button and either volume button. The reminder SHALL say it is a system feature and that the app does not send help on the runner's behalf. It SHALL NOT interrupt "开始跑步". It SHALL NOT be spoken when the page opens on an order that is already `IN_PROGRESS`.

#### Scenario: Countdown completes
- **WHEN** the order moves from `DRIVER_ARRIVED` to `IN_PROGRESS` and the countdown finishes
- **THEN** the reminder SHALL be queued after "开始跑步"
