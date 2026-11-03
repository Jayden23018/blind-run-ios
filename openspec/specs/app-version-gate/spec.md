# app-version-gate Specification

## Purpose
TBD - created by archiving change enforce-minimum-app-version. Update Purpose after archive.
## Requirements
### Requirement: The client compares its version numerically against the server's requirements
The client SHALL read `GET /api/config/app-version` without authentication at launch, when the session state changes, when an escort ends, and each time the scene returns to `.active`. Versions SHALL be compared segment by segment as numbers, and a missing trailing segment SHALL count as zero.

#### Scenario: Multi-digit segment
- **WHEN** the current version is `1.9` and the required version is `1.10`
- **THEN** the current version SHALL be treated as lower

#### Scenario: Equal versions of different length
- **WHEN** the current version is `1.0` and the required version is `1.0.0`
- **THEN** the versions SHALL be treated as equal

### Requirement: The version check never blocks on missing or bad data
The client SHALL NOT show any update prompt when the request fails for any reason, including 401 and 429, when a field is null, when a version string cannot be parsed, or when the update URL is missing or is not https. No result SHALL be cached across launches.

#### Scenario: Backend not deployed
- **WHEN** the endpoint returns 401
- **THEN** the app SHALL behave as if no version requirement exists
- **AND** the session SHALL NOT be affected

#### Scenario: Unusable update URL
- **WHEN** the current version is below the minimum and `iosUpdateUrl` is null or uses a scheme other than https
- **THEN** no prompt SHALL appear

### Requirement: A version below the minimum shows a system alert with one action
When the current version is below `iosMinSupportedVersion`, the client SHALL show a system alert with a single 「去更新」 button that opens the update URL. The client SHALL NOT draw a separate page for it. The copy SHALL state that the version is too low and what to do, and SHALL NOT mention help or emergencies.

#### Scenario: Returning to the app without updating
- **WHEN** the user taps 「去更新」 and returns to the app while still below the minimum
- **THEN** the alert SHALL appear again

#### Scenario: Update link cannot be opened
- **WHEN** the system refuses to open the update URL
- **THEN** the alert SHALL appear again and say how to update manually

### Requirement: Update prompts wait for the escort to end
The client SHALL NOT show an update prompt while the order is `DRIVER_EN_ROUTE`, `DRIVER_ARRIVED` or `IN_PROGRESS`, while a session-expiry deferral or an emergency is open, or while the client cannot tell. Other order states SHALL NOT defer the prompt. The client SHALL NOT call `POST /api/emergency/trigger`.

#### Scenario: Running when the check returns
- **WHEN** the current version is below the minimum and the order is `IN_PROGRESS`
- **THEN** no prompt SHALL appear

#### Scenario: Escort ends
- **WHEN** a deferred requirement exists and the order leaves those three states
- **THEN** the prompt SHALL appear without waiting for the next foreground

#### Scenario: Order lookup fails
- **WHEN** the current version is below the minimum and the order lookup fails
- **THEN** no prompt SHALL appear

#### Scenario: Session restoration has not finished
- **WHEN** the check completes while the session is still being restored
- **THEN** no prompt SHALL appear until the restored state is known

### Requirement: A version below the latest shows a dismissible alert once per version
When the current version is below `iosLatestVersion` and not below the minimum, the client SHALL show a system alert with 「稍后」 and 「去更新」 after privacy consent. Once closed, the alert SHALL NOT appear again for the same latest version, across launches and accounts. A newer latest version SHALL prompt again.

#### Scenario: Closed prompt
- **WHEN** the user closes the alert for version `1.2.0` and the app returns to the foreground
- **THEN** the alert SHALL NOT appear

#### Scenario: Newer release
- **WHEN** the user closed the alert for `1.2.0` and the latest version becomes `1.3.0`
- **THEN** the alert SHALL appear

