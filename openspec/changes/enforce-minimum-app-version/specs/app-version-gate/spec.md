## ADDED Requirements

### Requirement: The client compares its version numerically against the server's requirements
The client SHALL read `GET /api/config/app-version` without authentication at launch, when the session state changes, and each time the scene returns to `.active`. Versions SHALL be compared segment by segment as numbers, and a missing trailing segment SHALL count as zero.

#### Scenario: Multi-digit segment
- **WHEN** the current version is `1.9` and the required version is `1.10`
- **THEN** the current version SHALL be treated as lower

#### Scenario: Equal versions of different length
- **WHEN** the current version is `1.0` and the required version is `1.0.0`
- **THEN** the versions SHALL be treated as equal

### Requirement: The version check never blocks on missing or bad data
The client SHALL NOT block the user and SHALL NOT show a prompt when the request fails for any reason, including 401 and 429, when a field is null, when a version string cannot be parsed, or when the update URL is missing or is not https. No result SHALL be cached across launches.

#### Scenario: Backend not deployed
- **WHEN** the endpoint returns 401
- **THEN** the app SHALL behave as if no version requirement exists
- **AND** the session SHALL NOT be affected

#### Scenario: A later check fails while the gate is showing
- **WHEN** the required-update screen is showing and the next check fails
- **THEN** the screen SHALL be removed

#### Scenario: Unusable update URL
- **WHEN** the current version is below the minimum and `iosUpdateUrl` is null or uses a scheme other than https
- **THEN** the user SHALL NOT be blocked

### Requirement: A version below the minimum shows a full-screen required update
When the current version is below `iosMinSupportedVersion` and the client knows there is no unfinished order and no open emergency, the client SHALL show a full-screen page over all routes, including the privacy consent and login screens. The page SHALL state the reason in speech and text, SHALL offer update, emergency call and repeat actions with touch targets of at least 64pt, and SHALL remove the screen behind it from the accessibility tree.

#### Scenario: Screen reader user
- **WHEN** the page appears
- **THEN** the reason SHALL be spoken
- **AND** the elements behind the page SHALL NOT exist in the accessibility tree

#### Scenario: Update link cannot be opened
- **WHEN** the system refuses to open the update URL
- **THEN** the page SHALL say and show how to update manually

### Requirement: The required-update page only offers local dialing
The page's emergency action SHALL open the existing local dial dialog titled 「紧急呼叫」 through `EmergencyDialer`, with copy stating that the app will not send a request for help. It SHALL NOT call `POST /api/emergency/trigger`.

#### Scenario: Runner on the page
- **WHEN** a runner activates the emergency action or Magic Tap
- **THEN** the dialog SHALL offer the primary contact when there is exactly one, then 120, then 110

#### Scenario: Volunteer on the page
- **WHEN** a volunteer activates the emergency action
- **THEN** the dialog SHALL offer 120 and 110 only

### Requirement: Version prompts never cover an order or an emergency
The client SHALL NOT show the required-update page or the optional prompt while the user has an unfinished order or an open emergency, or while the client cannot tell. A session-expiry deferral SHALL count as an unfinished order. The requirement SHALL be evaluated again on the next launch or return to the foreground.

#### Scenario: Running when the check returns
- **WHEN** the current version is below the minimum and the order is `IN_PROGRESS`
- **THEN** the page SHALL NOT appear and the existing help entry points SHALL stay usable

#### Scenario: Order lookup fails
- **WHEN** the current version is below the minimum and the order lookup fails
- **THEN** the page SHALL NOT appear

#### Scenario: Session restoration has not finished
- **WHEN** the check completes while the session is still being restored
- **THEN** the page SHALL NOT appear until the restored state is known

### Requirement: A version below the latest shows a dismissible prompt once per version
When the current version is below `iosLatestVersion` and not below the minimum, the client SHALL show a dismissible prompt after privacy consent. Once closed, the prompt SHALL NOT appear again for the same latest version, across launches and accounts. A newer latest version SHALL prompt again.

#### Scenario: Closed prompt
- **WHEN** the user closes the prompt for version `1.2.0` and the app returns to the foreground
- **THEN** the prompt SHALL NOT appear

#### Scenario: Newer release
- **WHEN** the user closed the prompt for `1.2.0` and the latest version becomes `1.3.0`
- **THEN** the prompt SHALL appear
