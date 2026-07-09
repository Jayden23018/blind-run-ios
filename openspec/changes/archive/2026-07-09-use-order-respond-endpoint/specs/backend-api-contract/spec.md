## MODIFIED Requirements

### Requirement: API contract documents volunteer order response endpoint

The canonical API contract MUST define `POST /api/orders/{id}/respond` as the volunteer endpoint for accepting or declining an order dispatch.

#### Scenario: Volunteer accepts an order
- **WHEN** a volunteer accepts an order
- **THEN** the client sends `POST /api/orders/{id}/respond`
- **AND** the request body contains `{"action":"ACCEPT"}`
- **AND** a successful response moves the order to `PENDING_ACCEPT`

#### Scenario: Volunteer declines a dispatch
- **WHEN** a volunteer declines a dispatch prompt
- **THEN** the client sends `POST /api/orders/{id}/respond`
- **AND** the request body contains `{"action":"DECLINE"}`
- **AND** the order remains available according to backend dispatch rules
