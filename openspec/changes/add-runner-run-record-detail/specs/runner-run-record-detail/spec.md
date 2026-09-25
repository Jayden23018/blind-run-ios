## ADDED Requirements

### Requirement: Runner post-run detail reads the run record
The runner post-run detail page SHALL load `RunRecordServing.record(orderId:)` (capability `post-run-record`) and SHALL be reachable from the runner records-tab row of a completed run and from the full-screen route link of the completed summary. It SHALL end with a link to the order page, where reviews are submitted.

#### Scenario: Records tab row
- **WHEN** a runner taps a completed run in the records tab
- **THEN** the app SHALL open the runner post-run detail for that order

#### Scenario: Reaching the review
- **WHEN** the runner activates "订单详情与评价" on the detail page
- **THEN** the app SHALL open the existing order page for that order

### Requirement: One swipe from the header to the narration
With VoiceOver running, the page SHALL put VoiceOver focus on the header once the record loads, the header SHALL be a single accessibility element, and the next element SHALL be "听这次跑步".

#### Scenario: Header sentence
- **WHEN** VoiceOver reads the header
- **THEN** it SHALL read date, time of day, partner, place, distance, moving time and average pace as "每公里X分Y秒"
- **AND** when `comparison` is present it SHALL say how much more or less than last time

#### Scenario: VoiceOver status changes
- **WHEN** VoiceOver is turned off while the page is open
- **THEN** the route map SHALL move to the top of the page without reloading
- **AND** turning VoiceOver on SHALL move it back into the "路线" section

### Requirement: No apostrophe pace notation
No text on the runner page, visible or spoken, SHALL use the `6'15"` notation; paces SHALL read like "6分15秒" or "每公里6分15秒".

#### Scenario: Split row
- **WHEN** a full-kilometre split is shown
- **THEN** it SHALL read like "第3公里，5分58秒，本次最快，步频每分钟171步。"
- **AND** the cadence clause SHALL be omitted when the split has no cadence

### Requirement: Narration tells the run in one passage
"听这次跑步" SHALL speak a generated passage covering time, partner, place, distance, moving time, pace, comparison, slowest and fastest kilometre, rests, cadence, and the latest volunteer message, and SHALL show the same text as a transcript. Activating it again SHALL stop it.

#### Scenario: Missing data
- **WHEN** a value such as cadence or comparison is null
- **THEN** its clause SHALL be left out
- **AND** the passage SHALL NOT say 0 in its place

### Requirement: Route as sound
"用声音走一遍路线" SHALL play the run as a tone whose pitch rises with speed, whose stereo position follows the route's east–west position, with N short beeps at kilometre N, a low tone at each rest and two rising tones at the end, at 0.45 s per 100 m and no longer than 45 s in total, showing "第 N 公里" on screen while it plays.

#### Scenario: No VoiceOver announcements
- **WHEN** the route sound is playing
- **THEN** the page SHALL NOT post VoiceOver announcements

#### Scenario: No pace data
- **WHEN** the record has no pace samples
- **THEN** the section SHALL be hidden

### Requirement: Speech and sound do not talk over each other
Starting the narration or the route sound SHALL stop the other and the app's own speech. When VoiceOver focus moves away from the playing control, playback SHALL pause, and activating the control again SHALL resume it. Leaving the page SHALL stop playback.

#### Scenario: Focus moves away
- **WHEN** VoiceOver focus leaves the playing control
- **THEN** playback SHALL pause and the control SHALL be labelled as resumable

### Requirement: Every record state is presented honestly
The runner page SHALL present loading, generating, insufficient-track, failed, unknown and network-error states the same way as the volunteer page, without fabricating data.

#### Scenario: No route
- **WHEN** the status is `INSUFFICIENT_TRACK` or `track` is null
- **THEN** the map SHALL be hidden and the page SHALL say "这次没有记录到完整路线"
- **AND** narration, splits and more data SHALL still be shown

#### Scenario: Missing phone data
- **WHEN** `steps`, `avgCadence` or `elevationGainM` is null
- **THEN** that row SHALL be hidden and SHALL NOT show 0

### Requirement: Runner sees the volunteer's cumulative service time
When `service.volunteerTotalServiceMinutes` is present, "更多数据" SHALL include a row with the volunteer's cumulative service time (D6). It SHALL NOT show a confirmation status (D5).

#### Scenario: Volunteer account deleted
- **WHEN** `volunteerTotalServiceMinutes` is null
- **THEN** the row SHALL be hidden
