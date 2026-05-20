## ADDED Requirements

### Requirement: A user can switch active role in the app

The system MUST allow one phone-number account to hold blind runner and volunteer roles and switch `activeRole` without issuing a different JWT.

#### Scenario: Role switch succeeds
- **WHEN** an authenticated user without active orders switches `activeRole` to `blind_runner` or `volunteer`
- **THEN** the backend stores the new active role and returns the updated user

### Requirement: Active orders block role switching

The system MUST block role switching when the user has any order in `accepted`, `arrived`, `in_progress`, or `emergency`.

#### Scenario: Active order exists
- **WHEN** a user with an `accepted`, `arrived`, `in_progress`, or `emergency` order requests a role switch
- **THEN** the backend returns `ACTIVE_ORDER_ROLE_SWITCH_BLOCKED` and keeps the current active role

### Requirement: Role switching is app state, not account separation

The system MUST not create separate accounts or tokens for blind runner and volunteer roles.

#### Scenario: Same token after switch
- **WHEN** a user switches active role
- **THEN** the same authenticated account remains valid and subsequent APIs use the updated `activeRole`
