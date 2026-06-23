## ADDED Requirements

### Requirement: Real network traffic uses one fixed cloud endpoint

Every non-Mock HTTP request MUST use `http://47.114.113.171`, and every non-Mock WebSocket connection MUST use the corresponding `ws://47.114.113.171` endpoint.

#### Scenario: Cloud client construction
- **WHEN** the app constructs a real API or WebSocket client in any build channel
- **THEN** its host is `47.114.113.171` and no user-configurable alternative is available

### Requirement: Mock remains frontend-only

The Development build MAY use Mock for offline UI and automated tests, and Mock MUST NOT make network requests.

#### Scenario: Offline frontend test
- **WHEN** Development selects Mock
- **THEN** API responses come from `MockAPIClient` without connecting to any server

### Requirement: Distribution builds are cloud locked

Demo and Production builds MUST use the fixed cloud endpoint and MUST NOT expose an environment switcher.

#### Scenario: Distribution launch
- **WHEN** a Demo or Production build launches
- **THEN** its effective environment is the fixed cloud service
