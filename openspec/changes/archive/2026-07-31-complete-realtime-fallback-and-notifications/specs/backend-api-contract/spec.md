## ADDED Requirements

### Requirement: API contract types the volunteer-location fallback
The canonical API contract MUST define a typed response for `GET /api/blind/volunteer-location` containing optional latitude, longitude, order identity, status, and an authoritative `updatedAt` timestamp or a documented no-data response.

#### Scenario: Fresh fallback location exists
- **WHEN** the authenticated blind runner has an eligible pre-service order with recent volunteer location
- **THEN** the endpoint returns the coordinate, matching order identity/status, and documented timestamp format

#### Scenario: Fallback location is unavailable
- **WHEN** no eligible order or recent volunteer location exists
- **THEN** the endpoint returns the documented empty-data or stable error shape without stale coordinates

### Requirement: Realtime notification fields are contractually defined
The canonical WebSocket contract MUST define notification envelope, priority, timestamp, event identity when available, and TTS/display fields used by iOS foreground handling.

#### Scenario: App notification is emitted
- **WHEN** the backend sends a general app notification
- **THEN** the payload uses one documented envelope and contains display text, optional TTS text, priority, timestamp, and stable identity semantics

### Requirement: Both peer-location directions are contractually defined
The canonical WebSocket contract MUST define `VOLUNTEER_LOCATION_UPDATE` and `BLIND_LOCATION_UPDATE` with order ID, latitude, longitude, and timestamp semantics so the global coordinator can route them without parsing raw feature-specific payloads.

#### Scenario: Backend forwards a peer location
- **WHEN** an eligible participant location is forwarded to the associated order participant
- **THEN** the message identifies the location owner by message type and contains the associated order ID and documented timestamp

### Requirement: Separation alerts have a stable realtime contract
The canonical WebSocket contract MUST define the production separation-alert message envelope, event type, priority, event identity, safe display text, and TTS text.

#### Scenario: Separation alert is emitted
- **WHEN** the backend detects that participants exceed the configured separation threshold
- **THEN** both role sockets receive a typed high-priority alert that can be routed and deduplicated without matching localized text
