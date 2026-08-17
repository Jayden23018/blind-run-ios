## 1. Repository Boundary

- [x] 1.1 Remove the tracked local backend implementation and backend-specific ignore rules.
- [x] 1.2 Remove the superseded Spring MVP change and generated RepoWiki content.

## 2. iOS Cloud Environment

- [x] 2.1 Reduce API environments to Mock and the fixed cloud endpoint, including persistence and UI-test launch behavior.
- [x] 2.2 Consolidate Info plist and ATS configuration for every app build configuration.
- [x] 2.3 Update unit tests, UI tests, and cloud E2E tooling for the fixed endpoint and code `000000`.

## 3. Documentation

- [x] 3.1 Make `AGENTS.md` and a new root `README.md` explicitly define this as an iOS frontend-only repository.
- [x] 3.2 Update all maintained docs and UI guidance to describe only the external cloud contract.
- [x] 3.3 Consolidate the canonical OpenAPI contract into `docs/07-api-contract.openapi.yaml`.

## 4. Validation

- [x] 4.1 Verify forbidden local-backend references are absent from tracked files.
- [x] 4.2 Run strict OpenSpec validation and iOS build/test validation across applicable configurations.
