## ADDED Requirements

### Requirement: Volunteer hears that they may leave when the runner cancels after arrival
When the runner cancels after the volunteer has marked arrival, the volunteer SHALL hear that they may leave the meeting point. The foreground notification `ORDER_CANCELLED_BY_BLIND_AFTER_ARRIVAL` SHALL NOT be suppressed as a duplicate of the status change, and SHALL be spoken from its `ttsText`. When the volunteer's order page is open in the arrived layout and the order becomes `CANCELLED`, the page SHALL switch to the runner-cancelled layout and its spoken sentence SHALL include "你可以离开集合点了" and that this does not count as the volunteer's cancellation.

#### Scenario: Notification while the order page is open
- **WHEN** an active order is registered and `ORDER_CANCELLED_BY_BLIND_AFTER_ARRIVAL` arrives
- **THEN** the notification SHALL be presented and spoken, not suppressed

#### Scenario: Order page leaves the arrived layout
- **WHEN** the page shows the arrived layout and the next order detail is `CANCELLED`
- **THEN** the page SHALL show the runner-cancelled layout
- **AND** the spoken sentence SHALL contain "你可以离开集合点了"
