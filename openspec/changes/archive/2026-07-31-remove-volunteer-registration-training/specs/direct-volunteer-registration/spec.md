## ADDED Requirements

### Requirement: Volunteer registration uses two user-facing steps
The iOS client SHALL present volunteer registration as basic identity information followed by native face verification, and SHALL NOT require training progress or quiz completion.

#### Scenario: Registration flow is displayed
- **WHEN** a volunteer opens an incomplete registration flow
- **THEN** the step indicator SHALL show only basic identity information and face verification
- **AND** the client SHALL NOT display course, progress, or quiz controls
- **AND** the client SHALL NOT call volunteer training endpoints

### Requirement: Successful face verification completes registration on the backend
The external backend MUST atomically mark the volunteer registration as `STEP_4_COMPLETED` with `canAcceptOrders = true` when the authoritative Step 3 face result becomes approved.

#### Scenario: Face verification result is approved
- **WHEN** `POST /api/volunteer/registration/step3/face-verify/result` returns an approved result
- **THEN** the backend registration status SHALL be `STEP_4_COMPLETED`
- **AND** `canAcceptOrders` SHALL be true
- **AND** the new registration SHALL NOT enter `STEP_4_TRAINING`

#### Scenario: Existing training-state volunteer is migrated
- **WHEN** an existing volunteer has `STEP_4_TRAINING` during rollout
- **THEN** the iOS client SHALL treat the main registration as completed without requiring a course or quiz action
- **AND** the client SHALL NOT automatically enable `isAvailable` or `wantsDispatch`
- **AND** the external backend SHOULD still normalize the account to `STEP_4_COMPLETED` with `canAcceptOrders = true`

### Requirement: Registration completion remains backend-authoritative
The iOS client SHALL show registration success after registration status reports `STEP_4_COMPLETED`, legacy `STEP_4_TRAINING`, or `canAcceptOrders = true`.

#### Scenario: Completed status is received
- **WHEN** registration status reports `STEP_4_COMPLETED`, legacy `STEP_4_TRAINING`, or `canAcceptOrders = true`
- **THEN** the client SHALL update shared registration state
- **AND** the client SHALL show and announce “注册完成，请返回首页开启可服务状态”
- **AND** the client SHALL provide an explicit return action
- **AND** the client SHALL NOT automatically enable `isAvailable` or `wantsDispatch`

#### Scenario: Face passes before completed status is visible
- **WHEN** face verification is approved but registration status does not yet report `STEP_4_TRAINING`, `STEP_4_COMPLETED`, or `canAcceptOrders = true`
- **THEN** the client SHALL display “活体已通过，注册状态同步中，无需课程或答题”
- **AND** the client SHALL refresh status every 5 seconds while the screen is active
- **AND** the client SHALL provide manual refresh
- **AND** the client SHALL NOT start another face-verification attempt

### Requirement: Legacy training APIs remain deprecated compatibility contracts
The maintained OpenAPI contract SHALL retain existing volunteer and administrator training operations for compatibility while marking them deprecated and stating that the iOS registration flow does not call them.

#### Scenario: Training contract is inspected
- **WHEN** a maintainer reads a volunteer or administrator training operation in the maintained OpenAPI document
- **THEN** the operation SHALL have `deprecated: true`
- **AND** its description SHALL state that it is not part of the current registration flow
- **AND** `STEP_4_TRAINING` and training statistics SHALL be described as legacy compatibility fields
