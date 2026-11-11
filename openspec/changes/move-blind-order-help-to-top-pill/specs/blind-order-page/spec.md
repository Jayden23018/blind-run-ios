## ADDED Requirements

### Requirement: Pre-departure order states use the v7 dark header and vertical timeline
When the order is `PENDING_MATCH`, `REMATCHING`, `PENDING_INTRO_CALL`, `SCHEDULED_CONFIRMED` or `PENDING_ACCEPT`, the runner's order page SHALL show a dark header (a small status line and a large title), then a white sheet with the meeting place, a time line, and a vertical timeline of five steps in this order: 匹配陪跑员, 商量见面安排, 等出发, 在集合点汇合, 开跑. Only the current step SHALL be expanded; the step after it SHALL show as one row prefixed "下一步"; two or more later steps SHALL fold into one row "还有 N 步 ›"; two or more finished steps SHALL fold into one row "已完成 N 步 ›". A folded row SHALL be at least 64pt tall over its whole width, SHALL expand in place when activated, and SHALL read as "后面还有 N 步：<step names>" or "已完成 N 步：<step names>". The page SHALL NOT show the guide rope in these states.

#### Scenario: Matching
- **WHEN** the order is `PENDING_MATCH`
- **THEN** 匹配陪跑员 SHALL be the expanded step, 商量见面安排 SHALL be the "下一步" row, and the other three steps SHALL fold into "还有 3 步 ›"
- **AND** the only bottom action SHALL be "取消匹配"

#### Scenario: Booked
- **WHEN** the order is `SCHEDULED_CONFIRMED`
- **THEN** the first two steps SHALL fold into "已完成 2 步 ›", 等出发 SHALL be expanded with "开跑前 1 小时会提醒你出门", 在集合点汇合 SHALL be the "下一步" row and 开跑 SHALL be one plain row

#### Scenario: Waiting line not yet confirmed by the backend
- **WHEN** the order is `PENDING_MATCH` or `REMATCHING`
- **THEN** the page SHALL NOT show "最晚开跑前半小时会有结果"

### Requirement: Help pill in the top-right corner before departure
In the five pre-departure states the order page SHALL show a "求助" pill in the top-right corner and SHALL NOT show a "求助与安全" button at the bottom. Its accessibility label SHALL be "求助与安全". Activating it SHALL open the existing help and safety hub. The hub's emergency path SHALL be decided by `BlindHomeSOSMode.resolve` only; in these states it SHALL offer local dialling (primary emergency contact, 120, 110) and SHALL NOT call `POST /api/emergency/trigger`. The emergency confirmation text SHALL stay exactly as locked in `AGENTS.md` §6.

#### Scenario: Help before the run
- **WHEN** the order is `SCHEDULED_CONFIRMED` and the runner activates the help pill
- **THEN** the help and safety hub SHALL open and its emergency button SHALL offer the local call dialog titled "紧急呼叫"
- **AND** no request SHALL be sent to `/api/emergency/trigger`

### Requirement: Secondary order actions live in the "···" menu
In `PENDING_INTRO_CALL` the top bar SHALL offer a "···" menu holding "更换陪跑员" (behind its existing confirmation). In `SCHEDULED_CONFIRMED` and `PENDING_ACCEPT` the menu SHALL hold "取消预约" (behind the existing cancel confirmation), the run-plan share entry, and "给陪跑员留言" when the order accepts a runner message. The top bar SHALL always offer back and "重复当前状态".

#### Scenario: Change volunteer during the intro call
- **WHEN** the order is `PENDING_INTRO_CALL` and the runner chooses "更换陪跑员" from the menu
- **THEN** the existing decline confirmation SHALL appear before any request is sent

## MODIFIED Requirements

### Requirement: Runner page keeps safety entry and in-place running transition
From `DRIVER_EN_ROUTE` on, the "求助与安全" button SHALL stay in the bottom action area in every step; before departure (`PENDING_MATCH`, `REMATCHING`, `PENDING_INTRO_CALL`, `SCHEDULED_CONFIRMED`, `PENDING_ACCEPT`) the help entry SHALL be the top-right pill instead. Entering `IN_PROGRESS` SHALL transform the same page in place rather than navigate to a new page. While running and after completion, the page SHALL show a tinted hero card (running teal, completed green) holding the side-by-side guide rope and the distance, duration and pace figures. The order page SHALL hide the bottom tab bar in every state, and SHALL therefore show a back button in every state including running and completed, so the page always has an exit.

#### Scenario: Run starts
- **WHEN** the order moves from `DRIVER_ARRIVED` to `IN_PROGRESS`
- **THEN** the hero card SHALL be replaced in place by the teal running hero and the bottom safety button SHALL keep its position

#### Scenario: Leaving during the run
- **WHEN** the order is `IN_PROGRESS` and the runner activates the back button
- **THEN** the app SHALL return to the home tab and the order SHALL keep running

#### Scenario: No tab bar on the order page
- **WHEN** the runner opens the order page in any state
- **THEN** the bottom tab bar SHALL NOT be visible
