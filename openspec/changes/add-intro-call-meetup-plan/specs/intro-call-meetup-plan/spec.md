## Purpose

接单前通话（`PENDING_INTRO_CALL`）聊完之后，陪跑员把电话里商定的见面安排写成一张安排单，盲人听完朗读、确认后才生效并随成单写进订单。

## ADDED Requirements

### Requirement: Meetup plan is attached to the intro-call round, not to the order status
The meetup plan SHALL live inside `PENDING_INTRO_CALL` and SHALL NOT add any order status. A plan SHALL carry an optional new start / end time, an optional new start place with GCJ-02 coordinates, an optional meet-spot note of at most 30 characters, an optional volunteer top colour, an optional runner top colour and a server-generated version. A field left empty SHALL mean "keep the original arrangement". Every submission SHALL increase the version by one and SHALL clear the runner's earlier confirmation.

#### Scenario: Volunteer submits without changing anything
- **WHEN** the volunteer submits a plan with no field changed
- **THEN** the plan SHALL still be created, and the submission SHALL count as the volunteer's acceptance

#### Scenario: Volunteer revises a plan the runner already heard
- **WHEN** the volunteer submits again while the runner is on the review screen
- **THEN** the version SHALL increase, the runner's earlier confirmation SHALL no longer count, and the runner SHALL hear "陪跑员已修改见面安排，请重新收听。" with focus moved back to the title

### Requirement: Top colours decode as an open set
Top colour values the client does not recognise SHALL degrade to an unknown colour instead of failing the whole response. An unknown or absent colour SHALL NOT be read aloud and SHALL NOT be shown as a colour name.

#### Scenario: Backend adds a new colour
- **WHEN** the plan carries a colour value the client does not know
- **THEN** the plan SHALL still be shown, and the colour sentence for that person SHALL be left out of the spoken plan

### Requirement: Intro-call sub-steps are derived from the plan and the return from background
The client SHALL derive the runner's sub-step from: whether a plan exists, the plan version, the version the runner has confirmed, and whether the app has come back from the background during this round. A server-side plan SHALL take priority over the local "came back" flag, so that reopening the page or relaunching the app returns to the review screen.

| Plan | Runner confirmed latest version | Came back from background | Runner | Volunteer |
|---|---|---|---|---|
| none | — | no | B1 待通话 | V1 等来电 |
| none | — | yes | B2 等安排 | V1 等来电 |
| present | no | any | B3 听安排、做确认 | V3 等跑者确认 |
| present | yes | any | 约好 | V3 等跑者确认 (until the order moves on) |

#### Scenario: Runner relaunches the app after the plan arrived
- **WHEN** a plan exists and the runner relaunches the app without any background return in this process
- **THEN** the runner SHALL see B3, not B1

#### Scenario: Volunteer revises after the runner confirmed an older version
- **WHEN** the runner confirmed version 1 and the plan is now version 2
- **THEN** the runner SHALL see B3 again

### Requirement: Only a return from the background counts as "back from the call"
The client SHALL treat the app as back from the phone call only when it reaches `active` after having been in `background` since it was last `active`. A trip through `inactive` alone (dial confirmation cancelled, permission alert, Control Center) SHALL NOT count. The real return sequence `background → inactive → active` SHALL count once.

#### Scenario: Runner cancels the dial confirmation
- **WHEN** the scene phase goes `active → inactive → active`
- **THEN** the runner SHALL stay on B1

#### Scenario: Runner comes back after the call
- **WHEN** the scene phase goes `active → inactive → background → inactive → active`
- **THEN** the runner SHALL move to B2 if no plan has arrived yet

### Requirement: Runner hears the plan item by item in a fixed order
On B3 the title SHALL be the first focus and SHALL read "陪跑员<称呼>已提交见面安排，共 N 项变更。", where N counts only a changed start time and a changed start place. Below the title each item SHALL be a separate accessibility element in this fixed order: start time → start place → meet-spot note → top colours → the fixed sentence "见面时由陪跑员主动上前，并告知姓氏。". A changed item SHALL say "已变更" right after its label and SHALL state the old and new values ("由 X 改为 Y"); an unchanged item SHALL NOT contain "改". When only the end time changed, the time item SHALL name the end time as the changed value. A changed start place SHALL also state the distance from the original place ("距原地点约 N 米") when both coordinates are known and the distance is at least 10 m. The runner's own name for the volunteer SHALL be read without the mask asterisk. "重复当前状态" on B3 SHALL read the whole plan again.

#### Scenario: Time and place both changed
- **WHEN** the original is "明天 7:00–8:00, 朝阳公园南门" and the plan changes it to "7:30–8:30, 朝阳公园东门" about 800 m away
- **THEN** the title SHALL say "共 2 项变更", the time item SHALL read "开跑时间，已变更：由明天 7 点改为 7 点 30，8 点 30 结束。" and the place item SHALL contain "由朝阳公园南门改为朝阳公园东门" and "距原地点约 800 米"

#### Scenario: Same place name, moved coordinates
- **WHEN** the plan keeps the name "朝阳公园南门" but its coordinates are about 800 m from the original
- **THEN** the place item SHALL count as changed and SHALL read "集合地点，已变更：仍为朝阳公园南门，距原地点约 800 米。"

#### Scenario: Nothing changed
- **WHEN** the plan keeps the original time and place
- **THEN** neither the time item nor the place item SHALL contain "改", and the title SHALL NOT claim any change

### Requirement: Confirm and dispute carry the same weight on B3
"确认见面安排" and "有异议，致电沟通" SHALL have the same height. "有异议，致电沟通" SHALL dial directly and keep the plan; the volunteer SHALL only receive another incoming-call notice and SHALL NOT learn that the runner disagreed.

#### Scenario: Runner disputes the plan
- **WHEN** the runner taps "有异议，致电沟通"
- **THEN** the phone call SHALL start, the plan SHALL stay, and the volunteer SHALL see the same "跑者正在来电" notice as for any call

### Requirement: Window countdown is always visible and speaks only twice
Both sides SHALL show a persistent countdown of the intro-call window, updated silently each minute. The client SHALL announce the remaining time once when 5 minutes remain and once when 1 minute remains; repeated polling SHALL NOT repeat an announcement. The announcement SHALL name the node it crossed ("剩余 5 分钟" at 298 seconds left), and if the page is first seen below a node it SHALL state the actual remaining minutes. On B3 the announcement SHALL add "请确认见面安排". Under 1 minute the countdown SHALL read "不到 1 分钟" and SHALL NOT disappear. The client SHALL NOT announce that the window has timed out on its own; it waits for the server.

#### Scenario: Polling from 6 minutes down to 0
- **WHEN** the client polls every few seconds from 6 minutes remaining down to 0
- **THEN** exactly one 5-minute announcement and exactly one 1-minute announcement SHALL be made

#### Scenario: Window about to end
- **WHEN** 40 seconds remain
- **THEN** the countdown SHALL read "剩余不到 1 分钟"

### Requirement: Timeout and failures are visible and audible
If the window ends while the runner is on B3, the runner SHALL first hear "本次见面安排未生效。" and then the existing continued-search sentence. If the runner's confirmation fails to reach the server, the runner SHALL stay on B3 and a banner above the confirm button SHALL show and announce that the confirmation was not delivered. A 409 `INTRO_CALL_PLAN_STALE` on confirmation SHALL be handled as a revised plan, not as an error.

#### Scenario: Confirmation hits a stale version
- **WHEN** the runner confirms and the server answers 409 `INTRO_CALL_PLAN_STALE`
- **THEN** the runner SHALL hear "陪跑员已修改见面安排，请重新收听。" and SHALL NOT hear an error

### Requirement: Volunteer screens never expose the runner's stance
V3 SHALL NOT show whether the runner is listening, agrees or disagrees. When the round ends without a match, V4 SHALL use one neutral sentence for every cause and SHALL stay on screen with a "返回首页" button instead of navigating away automatically. A rejected submission SHALL keep the form and show the error under the affected section; a runner-side schedule conflict SHALL NOT reveal the reason.

#### Scenario: Runner's schedule conflicts with the new time
- **WHEN** the volunteer's new time collides with another booking of the runner
- **THEN** the volunteer SHALL see only that the time is unavailable, without any mention of the runner's other bookings
