## MODIFIED Requirements

### Requirement: Pace chart, splits and timeline carry the numbers
The card SHALL include a pace chart with an `AXChartDescriptor`, a split list with each split's pace as text, and the in-run timeline ending with a line derived from `sosTriggered`.

#### Scenario: Tapping a split
- **WHEN** a split row is tapped and the map is shown
- **THEN** that kilometre SHALL be highlighted on the map with a bubble naming the kilometre and its pace
- **AND** the page SHALL scroll back to the top

#### Scenario: No SOS
- **WHEN** `sosTriggered` is false
- **THEN** the timeline SHALL end with "全程没有触发紧急求助"

## ADDED Requirements

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
