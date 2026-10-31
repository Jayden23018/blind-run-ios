## MODIFIED Requirements

### Requirement: External API contract remains documented

The frontend repository MUST retain the OpenAPI and WebSocket contracts needed to integrate with the external cloud service without specifying or maintaining its implementation stack.

#### Scenario: Client integration review
- **WHEN** an iOS engineer needs the server contract
- **THEN** the canonical OpenAPI and WebSocket documentation describe the external service at `blindrun.culiu-tech.com`
