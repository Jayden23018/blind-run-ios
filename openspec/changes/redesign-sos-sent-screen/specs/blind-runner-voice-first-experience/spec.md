## ADDED Requirements

### Requirement: Sent-request screen has one primary action
After an SOS is sent, the blind runner's full-screen status page SHALL offer exactly one primary action (call 120), SHALL group 110 and the primary contact behind one secondary action, and SHALL show when the request was sent.

#### Scenario: Request sent
- **WHEN** the screen shows a sent request
- **THEN** the only filled button SHALL be 「拨打120」 with 「急救电话」
- **AND** one outline button 「打 110 或紧急联系人」 SHALL open the shared call-options dialog with the message 「求助已经发出。你也可以自己打电话，请选择要拨打的号码。」
- **AND** cancelling SHALL be a quiet text button 「误触了？撤销求助」 with a 64 pt hit area that still asks for confirmation
- **AND** the header SHALL show the send time and how long ago, as 「刚刚」, 「N 分钟前」 or 「N 小时 M 分钟前」

#### Scenario: Re-trigger merged into the same request
- **WHEN** the request on screen has absorbed a later press
- **THEN** a timeline SHALL show 「发出求助」 and 「又按了一次，并入这一条」 with their times
- **AND** the timeline SHALL be hidden from VoiceOver

#### Scenario: Request not sent
- **WHEN** the request failed to send and no event exists
- **THEN** the actions SHALL be, in order, 「拨打120」, 「再发一次求助」, 「打 110 或紧急联系人」, and there SHALL be no cancel action

## MODIFIED Requirements

### Requirement: Re-trigger merged into the open emergency is announced as such
When the runner triggers SOS again and the backend merges it into the runner's open emergency (same `eventId`), the app SHALL say that no new request was created, SHALL NOT start a countdown, and SHALL present the sent-request screen again.

#### Scenario: Same eventId comes back
- **WHEN** the trigger response carries the `eventId` of the local active emergency and a status other than `COUNTDOWN`
- **THEN** screen and VoiceOver SHALL say "这次没有新建求助：你上一次的求助还在处理中，已更新你的位置，系统正在再次提醒客服跟进。若情况危急请立即拨打120或110。"
- **AND** the app SHALL NOT claim that a new request was sent or that contacts received a message
- **AND** the sent-request screen (screen 3b) SHALL be presented again

#### Scenario: Stale countdown deadline on a merged response
- **WHEN** the merged response has a dispatched status and a past, non-null `countdownEndsAt`
- **THEN** the app SHALL NOT count down and SHALL NOT offer the countdown cancel

#### Scenario: A different eventId comes back
- **WHEN** the trigger response carries a new `eventId`
- **THEN** the app SHALL use the status copy for a new request and SHALL NOT count it as a merge
