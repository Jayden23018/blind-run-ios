## ADDED Requirements

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
The card SHALL show avatars, "和X一起跑", date and place, the distance, moving time / average pace / cadence, steps / climb / rest, and the volunteer-service minutes with its time range, and SHALL NOT show any confirmation status such as "待确认".

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

#### Scenario: Existing messages
- **WHEN** the record has messages
- **THEN** they SHALL be shown read-only, with no composer on this page

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
