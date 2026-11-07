# runner-run-record-detail Specification

## Purpose
TBD - created by archiving change add-runner-run-record-detail. Update Purpose after archive.
## Requirements
### Requirement: Runner post-run detail reads the run record
The runner post-run detail page SHALL load `RunRecordServing.record(orderId:)` (capability `post-run-record`) and SHALL be reachable from the runner records-tab row of a completed run and from the full-screen route link of the completed summary. It SHALL end with a link to the order page, where reviews are submitted.

#### Scenario: Records tab row
- **WHEN** a runner taps a completed run in the records tab
- **THEN** the app SHALL open the runner post-run detail for that order

#### Scenario: Reaching the review
- **WHEN** the runner activates "订单详情与评价" on the detail page
- **THEN** the app SHALL open the existing order page for that order

### Requirement: One swipe from the header to the narration
With VoiceOver running, the page SHALL put VoiceOver focus on the header once the record loads, the header SHALL be a single accessibility element, and the next element SHALL be "听这次跑步". This element SHALL exist only in the accessibility tree while VoiceOver runs; with VoiceOver off the same control SHALL be a round button at the top right of the route map, 44pt visible and 64pt tappable, carrying the same accessibility identifier (owner decision 2026-11-07, #823: no large listen buttons on the page).

#### Scenario: Header sentence
- **WHEN** VoiceOver reads the header
- **THEN** it SHALL read date, time of day, place, distance, moving time and average pace as "每公里X分Y秒"
- **AND** it SHALL NOT name the partner (the page title is "户外跑步")
- **AND** when `comparison` is present it SHALL say how much more or less than last time

#### Scenario: VoiceOver status changes
- **WHEN** VoiceOver is turned off while the page is open
- **THEN** the route map SHALL move to the top of the page without reloading
- **AND** turning VoiceOver on SHALL move it back into the "路线" section

### Requirement: The map stays behind the record and fades as the page scrolls
With VoiceOver off and a usable route, the route map SHALL stay fixed at the top of the screen behind the page content. Scrolling the content up SHALL slide the header and cards over the map, blur the map, and then cover it with the page colour; scrolling back down SHALL reveal it again (owner feedback 2026-11-07, #823 round 2). The blur SHALL be a material layer over the map, not a blur applied to the map view. With Reduce Transparency on, the map SHALL only darken. The volunteer detail SHALL behave the same way.

#### Scenario: Scrolled past the map
- **WHEN** the content has scrolled by the height of the map below the navigation bar
- **THEN** the map SHALL be fully covered by the page colour

#### Scenario: Back at the top
- **WHEN** the content is scrolled back to the top
- **THEN** the map SHALL be fully visible, without blur

### Requirement: No apostrophe pace notation
No text on the runner page, visible or spoken, SHALL use the `6'15"` notation; paces SHALL read like "6分15秒" or "每公里6分15秒".

#### Scenario: Split row
- **WHEN** a full-kilometre split is shown
- **THEN** it SHALL read like "第3公里，5分58秒，本次最快，步频每分钟171步，累计用时18分48秒。"
- **AND** the visible split table SHALL show the cumulative time, the pace as "5分58秒" and the cadence, without a "最快" tag
- **AND** the cadence clause SHALL be omitted when the split has no cadence

### Requirement: Narration tells the run in one passage
"听这次跑步" SHALL speak a generated passage covering time, partner, place, distance, moving time, pace, comparison, slowest and fastest kilometre, rests, cadence, and the latest volunteer message. It SHALL NOT show the passage as text on the page (owner decision 2026-11-07, #823 round 2). Activating it again SHALL stop it.

#### Scenario: Listening
- **WHEN** the runner activates "听这次跑步"
- **THEN** the passage SHALL be spoken
- **AND** no transcript SHALL appear on the page

#### Scenario: Missing data
- **WHEN** a value such as cadence or comparison is null
- **THEN** its clause SHALL be left out
- **AND** the passage SHALL NOT say 0 in its place

### Requirement: No route sound
The runner page SHALL NOT offer the route sound ("用声音走一遍路线"): no round button, no VoiceOver element and no playback card (owner decision 2026-11-07, #823 round 2: the tones sounded like an air-raid siren). The route is described by the "路线" text and the narration.

#### Scenario: Route with pace samples
- **WHEN** the record has a route and pace samples
- **THEN** the page SHALL show only the "听这次跑步" control at the top right of the map

### Requirement: Speech and sound do not talk over each other
Starting the narration or reading the messages SHALL stop the other and the app's own speech. When VoiceOver focus moves away from the playing control, playback SHALL pause, and activating the control again SHALL resume it. Leaving the page SHALL stop playback.

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

### Requirement: Runner page records the run, not the partner
The header, small stats, "详细信息" grid and split table SHALL NOT name the volunteer (owner decision 2026-11-07, #823, which withdraws D6's cumulative-service row). The partner SHALL appear only in the "X的留言" title and the narration. No value SHALL show a confirmation status (D5).

#### Scenario: Cumulative service time present
- **WHEN** `service.volunteerTotalServiceMinutes` is present
- **THEN** the page SHALL NOT show the volunteer's cumulative service time

### Requirement: Runner reads and hears the volunteer's messages
When the record has volunteer messages, the page SHALL show a "X的留言" card after the pace chart and before "路线" with every volunteer message as text. Each message SHALL carry a "朗读留言" VoiceOver custom action (no visible button since 2026-11-07, #823). The action SHALL speak the messages through the same player as the narration: starting it SHALL stop the narration, activating it again SHALL stop it, and VoiceOver focus leaving it SHALL pause it. The page SHALL NOT offer a reply control in this change.

#### Scenario: No volunteer message
- **WHEN** the record has no message from the volunteer
- **THEN** the section SHALL NOT be shown

#### Scenario: Narration running
- **WHEN** "朗读留言" is activated while the narration is playing
- **THEN** that playback SHALL stop and the messages SHALL be spoken

### Requirement: Pace colour on the route has a legend
When the route is coloured by pace, the "配速" card SHALL show the same "快 ▬ 慢" legend as the volunteer detail, in the same colours as the route. The top-left corner of the map holds the back button since 2026-11-07 (#823), so the legend is no longer drawn on the map.

#### Scenario: Pace samples present
- **WHEN** the record has at least two pace samples
- **THEN** the "配速" card SHALL show the legend under the chart

### Requirement: Listen is one swipe after the header in every state
The "听这次跑步" control SHALL directly follow the header in VoiceOver order whenever a narration exists, including when the record has no usable route. The "这次没有记录到完整路线" notice SHALL come after it.

#### Scenario: Insufficient track
- **WHEN** the record status is `INSUFFICIENT_TRACK` and a narration exists
- **THEN** one swipe right from the header SHALL land on "听这次跑步"
