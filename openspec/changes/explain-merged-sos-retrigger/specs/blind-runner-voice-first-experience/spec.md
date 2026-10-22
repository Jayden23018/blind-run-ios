## ADDED Requirements

### Requirement: Re-trigger merged into the open emergency is announced as such
When the runner triggers SOS again and the backend merges it into the runner's open emergency (same `eventId`), the app SHALL say that no new request was created, SHALL NOT start a countdown, and SHALL present the sent-request screen again.

#### Scenario: Same eventId comes back
- **WHEN** the trigger response carries the `eventId` of the local active emergency and a status other than `COUNTDOWN`
- **THEN** screen and VoiceOver SHALL say "这次没有新建求助：你上一次的求助还在处理中，已更新你的位置，系统正在再次提醒客服跟进。若情况危急请立即拨打110。"
- **AND** the app SHALL NOT claim that a new request was sent or that contacts received a message
- **AND** the sent-request screen (screen 3b) SHALL be presented again

#### Scenario: Stale countdown deadline on a merged response
- **WHEN** the merged response has a dispatched status and a past, non-null `countdownEndsAt`
- **THEN** the app SHALL NOT count down and SHALL NOT offer the countdown cancel

#### Scenario: A different eventId comes back
- **WHEN** the trigger response carries a new `eventId`
- **THEN** the app SHALL use the status copy for a new request and SHALL NOT count it as a merge
