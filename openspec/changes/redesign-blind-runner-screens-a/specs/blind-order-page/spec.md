## MODIFIED Requirements

### Requirement: Runner order page uses the volunteer v2 layout before the run
For the matching, booked, departed and met-up steps, the runner's order page SHALL render a hero card (eyebrow, guide rope, headline or large number, supporting lines), followed by a volunteer card when a volunteer is assigned and an info card. The hero card SHALL be tinted with the order-state colour shared with the volunteer page — booked navy, departed blue, met-up and countdown amber — and its text SHALL use the translucent white tones already verified at ≥4.5:1 on every state colour. While matching (no volunteer assigned) the hero SHALL stay a light card. The hero's visible headline SHALL be part of the same sentence its accessibility label reads. The meeting place SHALL be a tappable v2 place row only when the page can open a map; otherwise it SHALL be a row inside the info card. The page SHALL NOT render the four-segment progress bar.

#### Scenario: Booked order with a start time
- **WHEN** the order is `SCHEDULED_CONFIRMED` or `PENDING_ACCEPT` and has a planned start
- **THEN** the hero SHALL be tinted navy and show the start clock as the large number with unit "开跑" and an eyebrow "已约好 · <day part>"

#### Scenario: Matching order
- **WHEN** the order is `PENDING_MATCH`
- **THEN** the hero SHALL be a light card, its headline SHALL be the existing presentation title, and no volunteer card SHALL be shown

#### Scenario: Volunteer arrived
- **WHEN** the order is `DRIVER_ARRIVED`
- **THEN** the hero SHALL be tinted amber and its text SHALL be white

### Requirement: Runner page keeps safety entry and in-place running transition
The "求助与安全" button SHALL stay in the bottom action area in every step, and entering `IN_PROGRESS` SHALL transform the same page in place rather than navigate to a new page. While running and after completion, the page SHALL show a tinted hero card (running teal, completed green) holding the side-by-side guide rope and the distance, duration and pace figures. The order page SHALL hide the bottom tab bar in every state, and SHALL therefore show the back button in every state including running and completed, so the page always has an exit.

#### Scenario: Run starts
- **WHEN** the order moves from `DRIVER_ARRIVED` to `IN_PROGRESS`
- **THEN** the hero card SHALL be replaced in place by the teal running hero and the bottom safety button SHALL keep its position

#### Scenario: Leaving during the run
- **WHEN** the order is `IN_PROGRESS` and the runner activates the back button
- **THEN** the app SHALL return to the home tab and the order SHALL keep running

#### Scenario: No tab bar on the order page
- **WHEN** the runner opens the order page in any state
- **THEN** the bottom tab bar SHALL NOT be visible
