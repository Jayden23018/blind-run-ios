## Why

AidRun's server is now an external cloud service. Keeping a repository-local Spring Boot implementation, local server configuration, and conflicting documentation makes the iOS client easy to run against the wrong contract.

## What Changes

- Define this repository as the native iOS frontend repository only.
- Remove the repository-local backend, backend build configuration, and generated documentation derived from it.
- Keep Mock as an offline frontend test facility while fixing every real network request to `http://47.114.113.171`.
- Consolidate the cloud OpenAPI contract and update project documentation and validation commands.

## Capabilities

### New Capabilities

- `frontend-repository-boundary`: Defines the repository ownership boundary and prohibits backend implementation artifacts.
- `cloud-only-api-environment`: Defines Mock versus the single fixed cloud network environment.

### Modified Capabilities

- `backend-api-contract`: Becomes an external cloud API contract consumed by iOS rather than a backend implementation specification.

## Impact

- Removes `backend/`, the superseded Spring MVP change, and `.qoder/repowiki`.
- Simplifies iOS environment configuration, Info plist handling, tests, and cloud E2E tooling.
- Makes `docs/07-api-contract.openapi.yaml` the canonical cloud API contract.
