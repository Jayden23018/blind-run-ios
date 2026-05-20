## ADDED Requirements

### Requirement: Backend exposes Spring Boot REST API with OpenAPI docs

The backend MUST expose REST endpoints documented through Swagger/OpenAPI and MUST not use WebSocket for MVP status updates.

#### Scenario: Swagger available
- **WHEN** the Spring Boot backend starts
- **THEN** Swagger/OpenAPI documentation lists the MVP auth, user, profile, volunteer, and order endpoints

### Requirement: Backend uses H2 with seed data for demo

The backend MUST use H2 for demo storage and seed test users, profiles, orders, and points records at startup.

#### Scenario: Fresh local startup
- **WHEN** the backend starts with an empty H2 database
- **THEN** demo data is available for local and LAN iOS testing

### Requirement: API uses required MVP error codes

The backend MUST return stable error codes for known MVP failures.

#### Scenario: Known validation failure
- **WHEN** a request fails due to known MVP business rules
- **THEN** the response includes one of `INVALID_VERIFICATION_CODE`, `PROFILE_INCOMPLETE`, `LOCATION_PERMISSION_REQUIRED`, `ORDER_NOT_FOUND`, `ORDER_ALREADY_ACCEPTED`, `INVALID_ORDER_STATUS`, `ACTIVE_ORDER_ROLE_SWITCH_BLOCKED`, `VOLUNTEER_NOT_AVAILABLE`, `VOLUNTEER_NOT_APPROVED`, or `APPOINTMENT_TOO_SOON`

### Requirement: API contract covers all required MVP endpoints

The OpenAPI contract MUST define endpoints for phone login, current user, active role switch, profiles, Mock verification, availability, order creation, my orders, available orders, accept, arrive, confirm start, complete, cancel, emergency, rating, service records, points, and placeholder shop items.

#### Scenario: Client generation review
- **WHEN** an iOS engineer reviews the OpenAPI contract
- **THEN** every required MVP network call has a documented path, request body, response body, and authentication rule
