# direct-volunteer-registration Specification

## Purpose
TBD - created by archiving change remove-volunteer-registration-training. Update Purpose after archive.
## Requirements
### Requirement: Volunteer registration uses two user-facing steps
The iOS client SHALL present volunteer registration as an intro page followed by three steps: identity (name, ID card number, phone), running experience (optional, skippable), and native face verification. The client SHALL submit the identity and experience fields in one existing basic-info request, and SHALL NOT require training progress or quiz completion.

#### Scenario: Registration flow is displayed
- **WHEN** a volunteer opens an incomplete registration flow at the basic-info step
- **THEN** the client SHALL first show an intro page that lists the three steps
- **AND** the intro page SHALL offer a start action and an action to verify with uploaded identity materials instead of the face
- **AND** the client SHALL NOT display course, progress, or quiz controls
- **AND** the client SHALL NOT call volunteer training endpoints

#### Scenario: Identity step is incomplete
- **WHEN** the volunteer is on step 1 and name, ID card number, or phone is missing or invalid
- **THEN** the step header SHALL read “第 1 步，共 3 步”
- **AND** the next action SHALL be disabled
- **AND** the client SHALL show which fields are still missing below the next action

#### Scenario: Experience step is submitted or skipped
- **WHEN** the volunteer taps next or skip on step 2
- **THEN** the client SHALL ask for the separate identity and face consent if it has not been recorded
- **AND** after consent the client SHALL submit name, phone, ID card, running experience, guided-before, and emergency experience in one `POST /api/volunteer/registration/step1` request
- **AND** skip SHALL NOT clear fields the volunteer has already entered

#### Scenario: Volunteer chose identity materials on the intro page
- **WHEN** the volunteer tapped the identity-materials action on the intro page and the basic-info submission moves registration to face verification
- **THEN** the client SHALL call the existing face-verification decline endpoint instead of announcing face verification
- **AND** the client SHALL show the existing alternative-path landing page with the upload entry

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
The iOS client SHALL show the readiness progress page after registration status reports `registrationCompleted = true`, `STEP_4_COMPLETED`, or legacy `STEP_4_TRAINING`. The client MUST NOT present this moment as the end of the path to accepting orders.

#### Scenario: Completed status is received
- **WHEN** registration status reports `registrationCompleted = true`, `STEP_4_COMPLETED`, or legacy `STEP_4_TRAINING`
- **THEN** the client SHALL update shared registration state only when the user leaves the flow
- **AND** the client SHALL show the readiness progress page
- **AND** the client SHALL announce “实名和人脸认证已完成，请查看接单前还差哪几步”
- **AND** the client SHALL NOT show “注册完成”
- **AND** the client SHALL provide an explicit return action
- **AND** the client SHALL NOT automatically enable `isAvailable` or `wantsDispatch`

#### Scenario: Face passes before completed status is visible
- **WHEN** face verification is approved but registration status does not yet report completion
- **THEN** the client SHALL display “活体已通过，正在同步注册状态”
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

