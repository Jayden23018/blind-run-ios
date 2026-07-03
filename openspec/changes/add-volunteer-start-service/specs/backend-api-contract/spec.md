## MODIFIED Requirements

### Requirement: API contract documents volunteer service-start endpoint
The canonical API contract MUST define `POST /api/orders/{id}/start-service` as the volunteer endpoint for starting service after arrival.

#### Scenario: Volunteer starts service
- **WHEN** a volunteer starts service for an order in `DRIVER_ARRIVED`
- **THEN** the client sends `POST /api/orders/{id}/start-service`
- **AND** the request has no body
- **AND** a successful response moves the order to `IN_PROGRESS`

#### Scenario: Service start is rejected outside arrival state
- **WHEN** a volunteer calls `POST /api/orders/{id}/start-service` for an order not in `DRIVER_ARRIVED`
- **THEN** the backend returns the unified error response with `INVALID_ORDER_STATUS`
