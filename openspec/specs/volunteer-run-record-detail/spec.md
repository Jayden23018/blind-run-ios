# volunteer-run-record-detail Specification

## Purpose
TBD - created by archiving change add-volunteer-run-record-detail. Update Purpose after archive.
## Requirements
### Requirement: Volunteer post-run detail reads the run record
The volunteer post-run detail page SHALL load `RunRecordServing.record(orderId:)` (capability `post-run-record`) and SHALL be reachable from the volunteer records-tab row of a completed run and from the full-screen route link of the completed summary.

#### Scenario: Records tab row
- **WHEN** a volunteer taps a completed run in the records tab
- **THEN** the app SHALL open the post-run detail for that order without first loading the order detail

### Requirement: Route map shows pace, kilometres, start/end and rests
When the record has a `track`, the page SHALL show a map with the route drawn as a near-black outline under a line coloured by pace, kilometre markers, start and end markers, and rest markers, fitted inside the area above the card.

#### Scenario: Pace colouring
- **WHEN** the route is drawn
- **THEN** pace SHALL map linearly from the 5th percentile (fast) to the 95th percentile (slow) of `paceSamples` onto the fast → mid → slow palette
- **AND** every pace colour SHALL reach at least 3:1 against the outline

#### Scenario: Start and end coincide
- **WHEN** the first and last track points are within 50 m
- **THEN** a single "起终点" marker SHALL be shown instead of two

#### Scenario: Map accessibility
- **WHEN** VoiceOver reaches the map
- **THEN** it SHALL read one description of the route (distance, whether start and end coincide, number of rests)
- **AND** individual markers SHALL NOT be exposed

### Requirement: Card shows the run summary without confirmation status
The page SHALL show, under the full-width map, the place, the title "户外跑步", the distance and the date with start–end time; then the volunteer-service minutes with its time range; then a "详细信息" grid with moving time, distance, average pace, climb, steps, cadence, total time and rest. It SHALL NOT name the runner outside the messages (owner decision 2026-11-07, #823), and SHALL NOT show any confirmation status such as "待确认".

#### Scenario: Missing phone data
- **WHEN** `steps`, `avgCadence` or `elevationGainM` is null
- **THEN** that value and its label SHALL be hidden
- **AND** the page SHALL NOT show 0 in its place

#### Scenario: Pace wording
- **WHEN** a pace is shown on screen
- **THEN** it MAY be written like `6'15"`
- **AND** its accessibility text SHALL read like "每公里6分15秒"

#### Scenario: Largest text sizes
- **WHEN** the text size is an accessibility size
- **THEN** the stat columns SHALL stack vertically without truncation

### Requirement: Pace chart, splits and timeline carry the numbers
The card SHALL include a pace chart with an `AXChartDescriptor`, a split list with each split's pace as text, and the in-run timeline ending with a line derived from `sosTriggered`.

#### Scenario: Tapping a split
- **WHEN** a split row is tapped and the map is shown
- **THEN** that kilometre SHALL be highlighted on the map with a bubble naming the kilometre and its pace
- **AND** the page SHALL scroll back to the top

#### Scenario: No SOS
- **WHEN** `sosTriggered` is false
- **THEN** the timeline SHALL end with "全程没有触发紧急求助"

### Requirement: Every record state is presented honestly
The page SHALL present loading, generating, insufficient-track, failed, unknown and network-error states without fabricating data.

#### Scenario: Generating
- **WHEN** the status is `GENERATING`
- **THEN** the page SHALL say "记录正在生成，大约 1 分钟后可以查看"
- **AND** it SHALL re-read the record automatically until the status changes or the page closes

#### Scenario: No route
- **WHEN** the status is `INSUFFICIENT_TRACK` or `track` is null
- **THEN** the map SHALL be hidden and the page SHALL say "这次没有记录到完整路线"
- **AND** the remaining data SHALL still be shown

#### Scenario: Failed or network error
- **WHEN** the status is `FAILED`, unknown, or the request fails
- **THEN** the page SHALL say what happened and offer "重试"

### Requirement: Volunteer leaves a text message for the runner
The page SHALL list the run's messages and SHALL offer a composer — a text box, three quick phrases and a send button — that posts through `RunRecordServing.postMessage(orderId:text:)`. The text SHALL be trimmed and SHALL be 1–200 UTF-16 units before it is sent. More than one message per run SHALL be allowed.

#### Scenario: Blank or too long
- **WHEN** the trimmed text is empty or longer than 200 units
- **THEN** nothing SHALL be sent
- **AND** the reason SHALL be shown and spoken

#### Scenario: Sent
- **WHEN** the backend accepts the message
- **THEN** the box SHALL be cleared, the message SHALL appear in the list, and the page SHALL say "已发送。X在这条跑步记录里可以听到这句话。"
- **AND** the app SHALL NOT claim the runner has been notified or that the message is kept for any period

#### Scenario: Failed
- **WHEN** the request fails
- **THEN** the draft SHALL be kept
- **AND** the page SHALL show and speak "留言没有发出。" followed by the reason for the network error or error code

#### Scenario: Partner deregistered
- **WHEN** `blindName` is null
- **THEN** there SHALL be no composer and the page SHALL say "对方已注销账号，留言无法送达。"
- **AND** existing messages SHALL still be shown

### Requirement: Pace colour on the route has a legend and a spoken meaning
When the route is coloured by pace, the "配速" card SHALL show a "快 ▬ 慢" legend drawn in the same palette as the route (moved off the map on 2026-11-07, #823: the map's top-left corner holds the back button). The legend SHALL NOT be a separate VoiceOver stop. The map's spoken description SHALL say what the colours mean and, when there is a fastest full kilometre, which one it was.

#### Scenario: Legend in the pace card
- **WHEN** the record has pace samples and the route is drawn
- **THEN** the "配速" card SHALL show the legend with the text "快" and "慢" at the two ends
- **AND** VoiceOver SHALL NOT stop on it

#### Scenario: Spoken description
- **WHEN** VoiceOver reaches the map description and the record has a fastest split
- **THEN** it SHALL include "颜色表示配速，蓝色快，黄色慢" and "第N公里最快"

#### Scenario: No pace samples
- **WHEN** the record has no pace samples (the route is one colour)
- **THEN** there SHALL be no legend and the description SHALL NOT mention colours

### Requirement: Spoken text carries the prototype's information without mask markers
Everything VoiceOver reads on the volunteer detail SHALL be free of name mask markers (`*`, `＊`). The pace chart and the send button SHALL say what the prototype's `data-vo` says.

#### Scenario: Message author
- **WHEN** the runner's name is masked (`陈*`) and the runner left a message
- **THEN** the message header SHALL still show "陈*"
- **AND** VoiceOver SHALL read "陈说：…"

#### Scenario: Pace chart rests
- **WHEN** the record has rests
- **THEN** the chart's spoken summary SHALL include "X 公里处休息" for each rest

#### Scenario: Send button
- **WHEN** VoiceOver reaches the send button
- **THEN** its hint SHALL say "X在这条跑步记录里可以听到这句话"

#### Scenario: Pace chart names the fastest kilometre
- **WHEN** the record has a fastest split
- **THEN** the chart's spoken summary SHALL include "第N公里最快"

#### Scenario: Cadence is read as an average
- **WHEN** the record has an average cadence
- **THEN** VoiceOver SHALL read it as "平均步频 每分钟N步"

