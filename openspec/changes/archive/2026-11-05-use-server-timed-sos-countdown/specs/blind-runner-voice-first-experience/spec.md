## ADDED Requirements

### Requirement: SOS countdown is timed by the server
The runner's long-press SOS SHALL register a server-side countdown (`useCountdown`) and follow the returned `countdownEndsAt`. Cancelling SHALL withdraw it on the server, and the spoken result SHALL distinguish a request that was never sent from one that was sent and then cancelled.

#### Scenario: Countdown accepted by the server
- **WHEN** the trigger response is `COUNTDOWN` with `countdownEndsAt`
- **THEN** the app SHALL count down to that instant, announcing every second that cancelling is still possible
- **AND** at the deadline it SHALL say only that the request is recorded and being processed

#### Scenario: Server did not take the countdown
- **WHEN** the trigger response has no `countdownEndsAt`
- **THEN** the app SHALL treat the request as already sent and SHALL NOT count down

#### Scenario: Cancel during the countdown
- **WHEN** the runner cancels and the server answers `CANCELLED`
- **THEN** the app SHALL say "已撤回。求助没有发出，没有通知任何人。" without mentioning contacts or SMS
- **AND** when the server answers `FALSE_ALARM` it SHALL use the owner-cancel copy
- **AND** when the request fails it SHALL say the request may already have been sent and keep the event

#### Scenario: Countdown recovered after reconnect
- **WHEN** `GET /api/emergency/active` returns the runner's own `COUNTDOWN` event with a future deadline
- **THEN** the app SHALL resume the countdown and SHALL NOT present it as sent
