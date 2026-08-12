## REMOVED Requirements

### Requirement: Volunteer readiness requires certification, administrator approval, availability, WebSocket, and location
**Reason**: 可选资质证书和管理员审核不再是主注册接单门槛；原要求也未表达后端权威的 `canAcceptOrders` / `STEP_4_COMPLETED` 状态。

**Migration**: 使用新增的“Volunteer readiness requires completed main registration, availability, WebSocket, and location”要求。

## ADDED Requirements

### Requirement: Volunteer readiness requires completed main registration, availability, WebSocket, and location
The iOS volunteer experience SHALL treat a volunteer as dispatch-ready only when profile requirements, backend-authoritative main registration completion, manual availability opt-in, WebSocket connection, and recent location reporting are satisfied. Optional certificate and administrator-review compatibility fields SHALL NOT replace or add to the main registration gate when registration status is available.

#### Scenario: Volunteer dispatch workbench is available after readiness gates
- **WHEN** a logged-in user has active role `VOLUNTEER`, a complete volunteer profile, `canAcceptOrders = true`, `registrationStep = STEP_4_COMPLETED`, or legacy `registrationStep = STEP_4_TRAINING`, plus `wantsDispatch/isAvailable = true`, WebSocket online state, and recent location reporting
- **THEN** the app SHALL present the volunteer dispatch workbench as ready to receive backend dispatches
- **AND** the app SHALL load readiness, active orders, recent orders, points, and statistics from `GET /api/volunteer/dispatch-summary`

#### Scenario: Volunteer dispatch is blocked before readiness gates
- **WHEN** the volunteer is missing profile data, main registration completion, manual availability opt-in, WebSocket connection, or location permission
- **THEN** the app SHALL present the not-ready reason
- **AND** the app SHALL block accepting dispatches from the UI and ViewModel action layer

#### Scenario: Dispatch readiness changes after connection or location reporting
- **WHEN** the volunteer home remains active after WebSocket connection, location reporting, or availability changes
- **THEN** the client SHALL refresh `GET /api/volunteer/dispatch-summary` after a short propagation delay
- **AND** the client SHALL continue refreshing the summary every 10 seconds while the home screen is active

#### Scenario: Backend omits the unavailable reason
- **WHEN** dispatch summary returns `canDispatch = false` with an absent or empty `notAvailableReasons`
- **THEN** the client SHALL state that the backend did not return an unavailable reason
- **AND** the client SHALL NOT synthesize `canDispatch = true` or bypass dispatch acceptance guards

#### Scenario: Optional certificate is not a main registration gate
- **WHEN** registration status reports `canAcceptOrders = true`, `STEP_4_COMPLETED`, or legacy `STEP_4_TRAINING`
- **AND** an optional `verificationStatus` or `adminReviewStatus` compatibility field is absent, pending, or rejected
- **THEN** the client SHALL treat the main registration gate as complete
- **AND** all remaining availability, WebSocket, location, and order-state guards SHALL still apply
