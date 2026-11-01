## MODIFIED Requirements

### Requirement: Real network traffic uses one fixed cloud endpoint

Every non-Mock HTTP request MUST use `https://blindrun.culiu-tech.com`, and every non-Mock WebSocket connection MUST use the corresponding `wss://blindrun.culiu-tech.com` endpoint. The host MUST be the domain named in the App filing. The retired IP address MUST NOT be used as a real endpoint, and plaintext `http` or `ws` MUST NOT be used.

#### Scenario: Cloud client construction
- **WHEN** the app constructs a real API or WebSocket client in any build channel
- **THEN** its host is `blindrun.culiu-tech.com`, its scheme is `https` or `wss`, and no user-configurable alternative is available

#### Scenario: Retired address is written back
- **WHEN** app source adds the retired IP address, with or without a scheme
- **THEN** the repository guard blocks the change

#### Scenario: Look-alike host is written
- **WHEN** app source adds a URL whose host only contains the filed domain, such as a longer host or another subdomain
- **THEN** the repository guard blocks the change
