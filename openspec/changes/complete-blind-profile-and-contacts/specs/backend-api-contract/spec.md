## ADDED Requirements

### Requirement: API contract defines blind identity verification status
The canonical API contract MUST define typed request and response schemas for `POST /api/blind/verify-identity` and MUST expose the authoritative identity verification status through the blind profile contract.

#### Scenario: Identity verification is submitted
- **WHEN** iOS sends `idCardName` and `idCardNumber` to `/api/blind/verify-identity`
- **THEN** the backend returns a documented verification status and safe user-facing message
- **AND** the response does not return the full identity-card number

#### Scenario: Unverified user attempts booking
- **WHEN** a blind-runner without approved identity attempts `POST /api/orders`
- **THEN** the backend rejects the request with a stable unified business error

### Requirement: API contract defines emergency-contact collection invariants
The canonical API contract MUST document the one-to-five contact limit, self-user authorization, masked phone behavior, and exactly-one-primary invariant for emergency-contact endpoints.

#### Scenario: Contact limit is exceeded
- **WHEN** a user with five contacts attempts to create another
- **THEN** the backend rejects the request with a stable unified business error

#### Scenario: Primary contact changes
- **WHEN** iOS calls the set-primary endpoint for an owned contact
- **THEN** the backend atomically marks that contact primary and clears the previous primary

#### Scenario: Final contact deletion is attempted
- **WHEN** a user attempts to delete their only emergency contact
- **THEN** the backend rejects the mutation and preserves the required contact
