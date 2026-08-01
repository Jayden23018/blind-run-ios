## MODIFIED Requirements

### Requirement: Realtime deduplication is safety aware
The app-lifetime coordinator SHALL route emergency follow-up by the strongest identity the backend supplies for each message — event ID where present, otherwise the message ID — without text-deduplicating distinct events. Emergency messages delivered inside an `APP_NOTIFICATION` envelope carry neither event ID nor order ID, so message identity is the only available key for those.

#### Scenario: Contact notification arrives off-screen
- **WHEN** a contact-notified event for the active emergency arrives while its service screen is absent
- **THEN** the coordinator SHALL deliver it to `EmergencyCoordinator` exactly once

#### Scenario: Same text belongs to another event
- **WHEN** two emergency messages carry different identities
- **THEN** both SHALL be routed even if the presented copy is identical

#### Scenario: Emergency copy is presented
- **WHEN** the coordinator presents any emergency event
- **THEN** it SHALL use client-owned copy rather than the backend-supplied display or TTS body

### Requirement: Role service replacement clears emergency routing state
The realtime coordinator SHALL detach and clear non-authoritative emergency routing state when authenticated user/token/role service changes, while same-user recovery follows the documented backend contract.

#### Scenario: Another user signs in
- **WHEN** the WebSocket service is replaced for a different authenticated user
- **THEN** prior emergency samples and pending presentation SHALL be cleared before the new service attaches
