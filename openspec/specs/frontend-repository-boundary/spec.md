# frontend-repository-boundary Specification

## Purpose
TBD - created by archiving change remove-local-backend-use-cloud-only. Update Purpose after archive.
## Requirements
### Requirement: Repository contains only the native iOS frontend

The repository MUST identify itself as the AidRun native iOS frontend repository and MUST NOT contain server source code, server database configuration, or server build and deployment tooling.

#### Scenario: Repository ownership review
- **WHEN** an engineer reviews the tracked project structure and primary documentation
- **THEN** the repository contains the iOS app and frontend test/tooling only, and `AGENTS.md` plus `README.md` state that the backend is external

### Requirement: External API contract remains documented

The frontend repository MUST retain the OpenAPI and WebSocket contracts needed to integrate with the external cloud service without specifying or maintaining its implementation stack.

#### Scenario: Client integration review
- **WHEN** an iOS engineer needs the server contract
- **THEN** the canonical OpenAPI and WebSocket documentation describe the external service at `47.114.113.171`

