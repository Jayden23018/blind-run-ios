## ADDED Requirements

### Requirement: Scheduled order card matches the order page's agreed screen
The volunteer home's scheduled order card SHALL use the same components as the order page v2 "agreed" screen: a raised primary action button for confirming departure and a neutral text button for releasing the order. Both buttons SHALL have a touch target of at least 64pt. Releasing the order SHALL require confirmation through the same bottom sheet the order page uses.

#### Scenario: Releasing from the home card
- **WHEN** the volunteer taps "我去不了" on a scheduled card
- **THEN** the order page's cancel confirmation sheet SHALL appear
- **AND** the order SHALL be released only after the volunteer chooses to cancel in that sheet

#### Scenario: Touch targets
- **WHEN** the scheduled card is shown at any Dynamic Type size
- **THEN** both the confirm button and the "我去不了" button SHALL be at least 64pt tall
