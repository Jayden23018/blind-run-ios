## MODIFIED Requirements

### Requirement: API contract documents the external cloud service

The canonical OpenAPI contract MUST describe the external service consumed by the iOS frontend and MUST declare `http://47.114.113.171` as its only server.

#### Scenario: Contract validation
- **WHEN** the canonical OpenAPI file is inspected
- **THEN** it contains one server entry for `http://47.114.113.171` and no local or placeholder production server
