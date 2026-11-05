## MODIFIED Requirements

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
