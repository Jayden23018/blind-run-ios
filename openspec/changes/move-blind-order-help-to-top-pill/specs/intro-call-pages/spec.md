## ADDED Requirements

### Requirement: Runner intro call is part of the order page
For the runner, `PENDING_INTRO_CALL` SHALL be shown on the order page itself as the timeline step "商量见面安排", not as a full-screen page over the order page. Before a meetup plan arrives the step SHALL show the existing call texts and a bottom button "致电陪跑员<掩码称呼>" (or "再次致电" after returning from the call). When a plan arrives the step SHALL list the plan items and the bottom SHALL show "有异议，致电沟通" and "确认见面安排" at the same height. Dialling SHALL use only `dialableCounterpartPhone`. The page SHALL NOT show call rounds or the counterpart's stance.

#### Scenario: Order enters the intro call
- **WHEN** the order moves from `PENDING_MATCH` to `PENDING_INTRO_CALL` while the order page is open
- **THEN** the order page SHALL change in place to the call step and no full-screen page SHALL appear

#### Scenario: Plan submitted
- **WHEN** the volunteer submits a meetup plan
- **THEN** the page SHALL list every plan item, show "确认见面安排" and "有异议，致电沟通", and move VoiceOver focus to the plan title
