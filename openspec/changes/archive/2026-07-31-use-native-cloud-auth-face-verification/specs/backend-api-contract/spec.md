## ADDED Requirements

### Requirement: API contract documents native Step 3 initialization
The canonical API contract MUST define `POST /api/volunteer/registration/step3/face-verify/init` as a JWT-authenticated request whose body contains only the Alibaba Cloud SDK `metaInfo` string and whose successful native SDK response contains `status = PENDING` and a non-empty `certifyId`.

#### Scenario: Native Step 3 initialization succeeds
- **WHEN** the authenticated iOS client submits a non-empty `metaInfo`
- **THEN** the backend derives the current user from the JWT
- **AND** the response contains `status = PENDING` and a non-empty `certifyId`
- **AND** the response does not require `certifyUrl`

#### Scenario: Native Step 3 initialization fails
- **WHEN** the backend cannot initialize Alibaba Cloud face verification
- **THEN** the response contains `status = ERROR` and a user-facing `message`
- **AND** the response does not present the failure as a successful `PENDING` response

### Requirement: Native Step 3 initialization creates a fresh ID_PRO attempt
The external backend MUST create a new single-use Alibaba Cloud App SDK `ID_PRO` verification attempt for every accepted Step 3 init request and MUST NOT reuse or cache a previous `certifyId`.

#### Scenario: Authenticated volunteer starts a new attempt
- **WHEN** the authenticated volunteer submits the current non-empty MetaInfo
- **THEN** the backend uses a unique `OuterOrderNo`, the configured `SceneId`, `ProductCode = ID_PRO`, JWT-derived `UserId`, `CertType = IDENTITY_CARD`, Step 1 approved `CertName` and `CertNo`, and `Model = MULTI_ACTION`
- **AND** the returned `certifyId` is newly issued for that attempt

#### Scenario: Volunteer retries after an SDK failure
- **WHEN** the client retries Step 3 after code `1001`, cancellation, or another non-submitted SDK failure
- **THEN** the backend initializes a different Alibaba Cloud attempt instead of returning the prior `certifyId`

### Requirement: API contract documents native Step 3 result lookup
The canonical API contract MUST define `POST /api/volunteer/registration/step3/face-verify/result` as accepting `certifyId` and returning one of `PENDING`, `APPROVED`, `REJECTED`, or `ERROR`.

#### Scenario: Native result remains pending
- **WHEN** Alibaba Cloud has not produced a final result for the submitted `certifyId`
- **THEN** the backend returns `status = PENDING`

#### Scenario: Native result is final
- **WHEN** Alibaba Cloud has produced a final result for the submitted `certifyId`
- **THEN** the backend returns `APPROVED`, `REJECTED`, or `ERROR` with an appropriate message
