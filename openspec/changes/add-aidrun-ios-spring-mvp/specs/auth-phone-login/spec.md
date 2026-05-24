## ADDED Requirements

### Requirement: Phone login creates or returns a user

The system MUST support phone-number login that automatically creates a user account on first successful login.

#### Scenario: First login creates account
- **WHEN** a new phone number submits verification code `123456`
- **THEN** the backend creates a `User`, assigns available roles, leaves `activeRole` unset until role selection, and returns a JWT access token

#### Scenario: Existing phone logs in
- **WHEN** an existing phone number submits verification code `123456`
- **THEN** the backend returns the existing user and a new JWT access token

### Requirement: Demo verification code is fixed

The system MUST accept only the fixed MVP verification code `123456` and MUST not integrate a real SMS provider.

#### Scenario: Invalid code is rejected
- **WHEN** a user submits any verification code other than `123456`
- **THEN** the backend returns `INVALID_VERIFICATION_CODE`

### Requirement: JWT protects authenticated APIs

The system MUST require JWT Bearer Auth for all protected user, profile, volunteer, and order APIs.

#### Scenario: Missing token
- **WHEN** a protected endpoint is called without a valid Bearer token
- **THEN** the backend rejects the request as unauthorized
