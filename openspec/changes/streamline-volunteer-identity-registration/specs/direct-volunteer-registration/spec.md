## MODIFIED Requirements

### Requirement: Volunteer registration uses two user-facing steps
The iOS client SHALL present volunteer registration as an intro page followed by three steps: identity (name and ID card number), running experience (optional, skippable), and native face verification. The client SHALL submit the identity and experience fields in one existing basic-info request, and SHALL NOT require training progress or quiz completion. The client SHALL NOT ask for a phone number in the registration flow, because the account phone was already verified at login.

#### Scenario: Registration flow is displayed
- **WHEN** a volunteer opens an incomplete registration flow at the basic-info step
- **THEN** the client SHALL first show an intro page that lists the three steps
- **AND** the intro page SHALL offer a start action and an action to verify with uploaded identity materials instead of the face
- **AND** the client SHALL NOT display course, progress, or quiz controls
- **AND** the client SHALL NOT call volunteer training endpoints

#### Scenario: Identity step is incomplete
- **WHEN** the volunteer is on step 1 and name or ID card number is missing or invalid
- **THEN** the step header SHALL read “第 1 步，共 3 步”
- **AND** the next action SHALL be disabled
- **AND** the client SHALL show which fields are still missing below the next action
- **AND** the identity step SHALL NOT show a phone field

#### Scenario: Experience step is submitted or skipped
- **WHEN** the volunteer taps next or skip on step 2
- **THEN** the client SHALL ask for the separate identity and face consent if it has not been recorded
- **AND** after consent the client SHALL submit name, ID card, running experience, guided-before, and emergency experience in one `POST /api/volunteer/registration/step1` request
- **AND** the request SHALL NOT contain `phone`
- **AND** skip SHALL NOT clear fields the volunteer has already entered

#### Scenario: Volunteer chose identity materials on the intro page
- **WHEN** the volunteer tapped the identity-materials action on the intro page and the basic-info submission moves registration to face verification
- **THEN** the client SHALL call the existing face-verification decline endpoint instead of announcing face verification
- **AND** the client SHALL show the existing alternative-path landing page with the upload entry

### Requirement: Registration completion remains backend-authoritative
The iOS client SHALL treat registration as complete only when registration status reports `registrationCompleted = true`, `STEP_4_COMPLETED`, or legacy `STEP_4_TRAINING`. The client MUST NOT present this moment as the end of the path to accepting orders.

#### Scenario: Completed status is received
- **WHEN** registration status reports completion and the volunteer did not decline face verification
- **THEN** the client SHALL announce “实名和人脸认证已完成，接单前还差哪几步，可以在首页点查看接单前进度”
- **AND** the client SHALL update shared registration state at once, so that the root route moves to the volunteer home without a tap
- **AND** the client SHALL NOT show a completion page or a “返回志愿者首页” action
- **AND** the client SHALL NOT show “注册完成”
- **AND** the client SHALL NOT automatically enable `isAvailable` or `wantsDispatch`

#### Scenario: Volunteer declined face verification
- **WHEN** registration status reports completion and face verification status is `DECLINED`
- **THEN** the client SHALL keep the volunteer on the alternative-path landing page with the upload entry
- **AND** the client SHALL update shared registration state only when the volunteer taps “返回志愿者首页”

#### Scenario: Face passes before completed status is visible
- **WHEN** face verification is approved but registration status does not yet report completion
- **THEN** the client SHALL display “活体已通过，正在同步注册状态”
- **AND** the client SHALL refresh status every 5 seconds while the screen is active
- **AND** the client SHALL provide manual refresh
- **AND** the client SHALL NOT start another face-verification attempt

## ADDED Requirements

### Requirement: One ID card registers one volunteer
When the basic-info submission fails because the ID card number is already used by another volunteer account, the iOS client SHALL stay on the identity page and SHALL show and announce “这个身份证号已经注册过志愿者，一个身份证只能注册一个志愿者账号。请用原来的账号登录；如果不是你本人注册的，请联系客服。”. The client MUST NOT tell the volunteer to check the ID card, because the ID card is valid.

#### Scenario: ID card already used by another volunteer account
- **WHEN** `POST /api/volunteer/registration/step1` returns the backend error code for an ID card already used by another volunteer account
- **THEN** the client SHALL show the identity page with the name and ID card fields
- **AND** the client SHALL show and announce the message above
