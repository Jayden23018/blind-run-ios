## 1. Contract and Documentation

- [x] 1.1 Update AGENTS.md and maintained docs to describe `POST /api/orders/{id}/respond`.
- [x] 1.2 Update the canonical OpenAPI contract with `OrderRespondRequest`.

## 2. iOS Client and Mock

- [x] 2.1 Add the Swift response request model and switch volunteer accept/decline calls to `/respond`.
- [x] 2.2 Update MockAPIClient to support `ACCEPT` and `DECLINE`.

## 3. Tests and E2E

- [x] 3.1 Update unit tests for the new request body and Mock order action.
- [x] 3.2 Update cloud E2E to use `/respond`.
- [x] 3.3 Run OpenSpec validation, script syntax checks, and iOS build/test validation where available.
