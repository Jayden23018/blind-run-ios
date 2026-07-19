## MODIFIED Requirements

### Requirement: Realtime deduplication is safety aware
The app-lifetime coordinator SHALL route emergency follow-up by event ID, order ID, authenticated participant, and role without text-deduplicating distinct events.

#### Scenario: Matching contact notification arrives off-screen
- **WHEN** a contact-notified event for the active participant/order arrives while its service screen is absent
- **THEN** the coordinator SHALL deliver it to `EmergencyCoordinator` exactly once

#### Scenario: Same text belongs to another event
- **WHEN** an emergency message has a different event or order identity
- **THEN** it SHALL NOT update the current event even if localized copy is identical

### Requirement: Role service replacement clears emergency routing state
The realtime coordinator SHALL detach and clear non-authoritative emergency routing state when authenticated user/token/role service changes, while same-user recovery follows the documented backend contract.

#### Scenario: Another user signs in
- **WHEN** the WebSocket service is replaced for a different authenticated user
- **THEN** prior emergency samples and pending presentation SHALL be cleared before the new service attaches
