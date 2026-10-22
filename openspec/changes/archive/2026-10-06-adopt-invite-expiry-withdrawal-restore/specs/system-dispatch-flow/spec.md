## MODIFIED Requirements

### Requirement: Volunteer receives timed dispatch prompts
The iOS volunteer client SHALL receive backend `NEW_ORDER` prompts through the app-lifetime realtime coordinator and retain accept/decline-only behavior.

#### Scenario: New order dispatch arrives
- **WHEN** `/ws/volunteer` receives a `NEW_ORDER` message
- **THEN** the app SHALL show a prompt whose reply deadline is the invite's `expiresAt` (the backend gives 60 or 15 minutes since #371; `dispatchTimeoutSeconds` is only the fallback)
- **AND** the prompt SHALL display order time, start address, distance, priority, optional pace, guide dog, notes, and optional start coordinates when present

#### Scenario: Dispatch arrives during navigation
- **WHEN** `/ws/volunteer` receives `NEW_ORDER` while volunteer home is not mounted
- **THEN** the coordinator SHALL retain and present the prompt until its `expiresAt`
- **AND** no public-order-pool or "later" action SHALL be introduced

#### Scenario: Volunteer accepts dispatch
- **WHEN** the volunteer taps accept on a dispatch prompt
- **THEN** the app SHALL report current location if available
- **AND** the app SHALL call `POST /api/orders/{id}/respond` with `action = ACCEPT`
- **AND** the app SHALL navigate to the accepted order detail or service flow on success

#### Scenario: Volunteer declines or times out
- **WHEN** the volunteer taps decline or the prompt timer reaches zero
- **THEN** the app SHALL call `POST /api/orders/{id}/respond` with `action = DECLINE` when appropriate
- **AND** the app SHALL dismiss the prompt without showing a "later" business action
