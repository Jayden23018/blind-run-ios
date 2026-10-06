## MODIFIED Requirements

### Requirement: API contract documents volunteer service-start endpoint
The canonical API contract MUST define `POST /api/orders/{id}/start-service` as the endpoint for starting service after arrival. Since backend #346 both the volunteer and the blind runner of the order MAY call it; the first call wins.

#### Scenario: Volunteer starts service
- **WHEN** a volunteer starts service for an order in `DRIVER_ARRIVED`
- **THEN** the client sends `POST /api/orders/{id}/start-service`
- **AND** the request has no body
- **AND** a successful response moves the order to `IN_PROGRESS`

#### Scenario: Blind runner starts service
- **WHEN** the blind runner starts service for an order in `DRIVER_ARRIVED`
- **THEN** the client sends `POST /api/orders/{id}/start-service` with the blind-runner token and no body
- **AND** the backend records the runner's consent and moves the order to `IN_PROGRESS`

#### Scenario: The other participant already started
- **WHEN** either participant calls `POST /api/orders/{id}/start-service` for an order already in `IN_PROGRESS`
- **THEN** the backend returns 200 without an error

#### Scenario: Service start is rejected outside arrival state
- **WHEN** a participant calls `POST /api/orders/{id}/start-service` for an order neither in `DRIVER_ARRIVED` nor in `IN_PROGRESS`
- **THEN** the backend returns the unified error response with `INVALID_ORDER_STATUS`
