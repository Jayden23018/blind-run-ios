## ADDED Requirements

### Requirement: Hero card colour follows the order state
The hero card SHALL use a state colour: agreed (`SCHEDULED_CONFIRMED`, `PENDING_ACCEPT`) and runner-cancelled use navy, `DRIVER_EN_ROUTE` uses the departed blue, `DRIVER_ARRIVED` uses the arrived amber, `COMPLETED` uses the done green; the invitation keeps the white card. Text on every state colour SHALL reach 4.5:1. When the state changes while the page is open, the card background SHALL cross-fade over 0.35 seconds. The state colours SHALL NOT be used outside the hero card, except the arrived direction dial, ring button and the emphasised call button after the wait threshold.

#### Scenario: Departing changes the hero colour
- **WHEN** the order moves from `PENDING_ACCEPT` to `DRIVER_EN_ROUTE` while the page is open
- **THEN** the hero card background SHALL change from navy to the departed blue with a 0.35-second transition

#### Scenario: Runner cancels
- **WHEN** the runner cancels the order
- **THEN** the hero card SHALL use navy

## MODIFIED Requirements

### Requirement: Rope is a single accessible element and motion respects Reduce Motion
The guide rope SHALL be exposed to VoiceOver as one element reading "第 N 步，共 4 步，{状态}" (plus remaining minutes when departed). When Reduce Motion is on, every position, scale and drawing animation on the order page (rope, direction dial, notice bar, primary-button upgrade, completion illustration) SHALL become a fade of at most 0.2 seconds and looping effects SHALL be static. Looping effects SHALL also stop when the app is not active. Colour transitions of the hero card are not motion and SHALL still apply.

#### Scenario: Reduce Motion
- **WHEN** Reduce Motion is enabled and the order becomes `DRIVER_EN_ROUTE`
- **THEN** the volunteer avatar SHALL appear at its new position without sliding and the glow SHALL NOT pulse

#### Scenario: Reduce Motion on arrival
- **WHEN** Reduce Motion is enabled and the order becomes `DRIVER_ARRIVED`
- **THEN** the direction dial SHALL fade in without scaling
