## ADDED Requirements

### Requirement: Records tab lists completed runs from the monthly history
Both roles' records tab SHALL show completed runs read from `RunRecordServing.monthlyRecords` (capability `post-run-record`) for one month at a time, with a month summary sentence and one row per completed run.

#### Scenario: Tab opens
- **WHEN** the records tab appears
- **THEN** it SHALL request the current calendar month
- **AND** it SHALL keep the backend's item order

#### Scenario: Runner row
- **WHEN** the signed-in role is the blind runner
- **THEN** each row SHALL show the finish date with weekday, the place and partner, and the distance in kilometres
- **AND** it SHALL NOT show a route thumbnail
- **AND** its accessibility label SHALL be one sentence such as "9月20日周六，深圳湾公园，和小林，5.21公里"

#### Scenario: Volunteer row
- **WHEN** the signed-in role is the volunteer
- **THEN** each row SHALL additionally show a route thumbnail drawn from the item's `thumbnail` points
- **AND** the thumbnail SHALL be hidden from accessibility
- **AND** its accessibility label SHALL read like "9月20日周六，陪老陈，深圳湾公园，5.21公里"

#### Scenario: Month summary
- **WHEN** the month has runs
- **THEN** the runner summary SHALL read like "9月跑了 5 次，一共 22.54 公里。"
- **AND** the volunteer summary SHALL read like "9月陪跑 4 次，服务 3 小时 40 分钟。其中和老陈跑了 3 次。"

#### Scenario: Masked partner names
- **WHEN** a partner name arrives masked (for example `张*`)
- **THEN** the visible text SHALL keep the mask
- **AND** no accessibility label SHALL contain the mask character

### Requirement: One month at a time with a month switcher
The records tab SHALL offer full-width rows to switch to the previous month and, unless the shown month is the current month, to the next month.

#### Scenario: Switch to the previous month
- **WHEN** the user activates "上个月"
- **THEN** the tab SHALL request the previous calendar month (January goes to December of the previous year)
- **AND** the unfinished-orders group SHALL stay as it was

#### Scenario: Current month has no next
- **WHEN** the shown month is the current month
- **THEN** no "下个月" control SHALL be shown

### Requirement: Unfinished bookings stay reachable
Cancelled and no-volunteer orders SHALL keep coming from `GET /api/orders/mine` and SHALL appear in a bottom group titled "未完成的预约", not filtered by month.

#### Scenario: Mixed order statuses
- **WHEN** `/api/orders/mine` returns completed, cancelled, no-volunteer, in-flight, and unknown-status orders
- **THEN** only the cancelled and no-volunteer ones SHALL appear in "未完成的预约"
- **AND** they SHALL be ordered newest first

### Requirement: Runner keeps the completed-runs rotor
The runner's records tab SHALL keep the custom VoiceOver rotor "已完成的跑步", whose entries SHALL be exactly the completed runs listed for the shown month.

#### Scenario: Rotor entries match the list
- **WHEN** the month's runs are loaded
- **THEN** every rotor entry SHALL correspond to a visible completed-run row

### Requirement: Every state is presented and missing values are hidden
The records tab SHALL present loading, empty, and error states, and SHALL hide any field whose value is `null` instead of showing `0`.

#### Scenario: Loading
- **WHEN** data is loading for the first time
- **THEN** a placeholder list SHALL be shown and read by VoiceOver as one element "正在加载跑步记录" (runner) or "正在加载陪跑记录" (volunteer)

#### Scenario: Never ran
- **WHEN** the shown month has no runs and `/api/orders/mine` has no completed order
- **THEN** the runner SHALL see "完成第一次陪跑后，记录会出现在这里"
- **AND** the volunteer SHALL see the same sentence followed by the hint about turning on availability

#### Scenario: Empty month
- **WHEN** the shown month has no runs but the user has completed orders
- **THEN** the tab SHALL say that month has no records and SHALL keep the month switcher

#### Scenario: Network error
- **WHEN** either request fails with a non-authentication error
- **THEN** the tab SHALL say what failed and offer a "重试" button that reloads
- **AND** data that did load SHALL stay visible

#### Scenario: Missing distance or service time
- **WHEN** an item's `distanceM`, or the summary's `distanceM` or `serviceMin`, is `null`
- **THEN** the corresponding text SHALL be omitted, never rendered as `0`

#### Scenario: Touch targets
- **WHEN** any row or button in the tab is rendered
- **THEN** its height SHALL be at least 64 points (`FlowMetrics.actionButtonMinHeight`)
