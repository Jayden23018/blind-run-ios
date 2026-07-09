# backend-api-contract Specification

## Purpose
Define the external cloud backend API and WebSocket contract requirements that the native iOS frontend depends on.
## Requirements
### Requirement: API contract documents the external cloud service

The canonical OpenAPI contract MUST describe the external service consumed by the iOS frontend and MUST declare `http://47.114.113.171` as its only server.

#### Scenario: Contract validation
- **WHEN** the canonical OpenAPI file is inspected
- **THEN** it contains one server entry for `http://47.114.113.171` and no local or placeholder production server

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

### Requirement: Volunteer dispatch requires recent WebSocket location

The canonical integration contract MUST require volunteers to connect `/ws/volunteer` and send a `LOCATION_UPDATE` before they can receive order dispatches or respond to dispatched orders.

#### Scenario: Volunteer becomes eligible for dispatch
- **WHEN** a volunteer is available and online
- **AND** the volunteer sends `{"type":"LOCATION_UPDATE","lat":number,"lng":number}` over `/ws/volunteer`
- **AND** the reported location is within 10 km of an order start point
- **THEN** the backend may include the order in `/api/orders/available` or send `NEW_ORDER`

#### Scenario: Volunteer responds before dispatch eligibility
- **WHEN** a volunteer sends `POST /api/orders/{id}/respond`
- **AND** the order has not been dispatched to that volunteer
- **THEN** the backend returns a business error such as `ORDER_DISPATCH_MISMATCH`

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

