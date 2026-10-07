## ADDED Requirements

### Requirement: Runner order page uses the volunteer v2 layout before the run
For the matching, booked, departed and met-up steps, the runner's order page SHALL render a light hero card (eyebrow, guide rope, headline or large number, supporting lines), followed by a volunteer card when a volunteer is assigned and an info card. The meeting place SHALL be a tappable v2 place row only when the page can open a map; otherwise it SHALL be a row inside the info card. The page SHALL NOT render the four-segment progress bar.

#### Scenario: Booked order with a start time
- **WHEN** the order is `SCHEDULED_CONFIRMED` or `PENDING_ACCEPT` and has a planned start
- **THEN** the hero SHALL show the start clock as the large number with unit "开跑" and an eyebrow "已约好 · <day part>"

#### Scenario: Matching order
- **WHEN** the order is `PENDING_MATCH`
- **THEN** the hero headline SHALL be the existing presentation title and no volunteer card SHALL be shown

### Requirement: Guide rope speaks from the runner's perspective
On the runner's page the guide rope's accessibility label SHALL state the step out of four in the runner's words, and the runner's own avatar SHALL read "我".

#### Scenario: Volunteer en route
- **WHEN** the order is `DRIVER_EN_ROUTE`
- **THEN** the rope label SHALL read "第 3 步，共 4 步，陪跑员正在赶来"

### Requirement: Runner page keeps safety entry and in-place running transition
The "求助与安全" button SHALL stay in the bottom action area in every step, and entering `IN_PROGRESS` SHALL transform the same page in place rather than navigate to a new page.

#### Scenario: Run starts
- **WHEN** the order moves from `DRIVER_ARRIVED` to `IN_PROGRESS`
- **THEN** the hero card SHALL be replaced in place by the running metrics card and the bottom safety button SHALL keep its position
