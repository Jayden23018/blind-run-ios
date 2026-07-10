## ADDED Requirements

### Requirement: API contract types the volunteer-location fallback
The canonical API contract MUST define a typed response for `GET /api/blind/volunteer-location` containing optional latitude, longitude, and an authoritative `updatedAt` timestamp or a documented no-data response.

#### Scenario: Fresh fallback location exists
- **WHEN** the authenticated blind runner has an eligible `DRIVER_EN_ROUTE` or `DRIVER_ARRIVED` order with recent volunteer location
- **THEN** the endpoint returns the coordinate and documented timestamp format

#### Scenario: Fallback location is unavailable
- **WHEN** no eligible order or recent volunteer location exists
- **THEN** the endpoint returns the documented empty-data or stable error shape without stale coordinates

### Requirement: Realtime notification fields are contractually defined
The canonical WebSocket contract MUST define priority, timestamp, event identity when available, and TTS/display fields used by iOS foreground notification handling.

#### Scenario: App notification is emitted
- **WHEN** the backend sends `APP_NOTIFICATION`
- **THEN** the payload contains documented `body`, optional `ttsText`, priority, and timestamp semantics
- **AND** any stable notification identifier used for deduplication is documented
