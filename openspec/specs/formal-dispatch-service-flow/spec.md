# formal-dispatch-service-flow Specification

## Purpose
Define the iOS formal dispatch and service lifecycle for blind-runner booking, volunteer readiness and dispatch response, canonical order-status routing, strict service completion gates, placeholder emergency behavior, and Mock/test coverage.

## Requirements

### Requirement: Blind runner profile and booking gate
The iOS app SHALL require a logged-in blind-runner user to select the blind role, complete the blind-runner profile, store at least one emergency contact, grant location access, and choose an appointment time at least 30 minutes in the future before submitting a booking.

#### Scenario: Blind runner can submit booking after required gates
- **WHEN** a logged-in user has active role `BLIND`, a complete blind-runner profile, at least one emergency contact, location permission, a start location, and an appointment time at least 30 minutes away
- **THEN** the app SHALL allow booking submission through `POST /api/orders`
- **AND** the app SHALL navigate to the order status flow when the backend returns an order ID

#### Scenario: Booking is blocked without required gates
- **WHEN** the blind-runner user lacks profile completion, emergency contact, location permission, start location, or a valid appointment time
- **THEN** the app SHALL block `POST /api/orders`
- **AND** the app SHALL show and speak a clear error prompt

### Requirement: Blind runner follows formal order lifecycle
The iOS blind-runner experience SHALL expose the formal order lifecycle from system dispatch through service completion and optional rating without skipping required lifecycle states.

#### Scenario: Blind runner waits through dispatch and arrival states
- **WHEN** an active blind-runner order is `PENDING_MATCH`, `PENDING_ACCEPT`, `DRIVER_EN_ROUTE`, or `DRIVER_ARRIVED`
- **THEN** the app SHALL show the status tracking experience
- **AND** the app SHALL update status from `ORDER_STATUS_CHANGED` WebSocket events or 5-second polling of `GET /api/orders/{id}`
- **AND** the app SHALL provide a "重复当前状态" action that speaks the latest meaningful status

#### Scenario: Blind runner can cancel a stuck rematching order
- **WHEN** an active blind-runner order is `REMATCHING`
- **THEN** the app SHALL keep rendering the real backend `REMATCHING` status
- **AND** the blind-runner home and order status views SHALL show a "取消订单" action with second confirmation
- **AND** confirmation SHALL call the existing `POST /api/orders/{id}/cancel` endpoint
- **AND** the request SHALL use the blind-runner token because the volunteer that cancelled is no longer an order participant
- **AND** release validation SHALL verify the backend-confirmed `REMATCHING -> CANCELLED` path

#### Scenario: Blind runner enters in-service state
- **WHEN** the active blind-runner order becomes `IN_PROGRESS`
- **THEN** the app SHALL show a blind-runner in-service experience
- **AND** the app SHALL keep polling or listening for completion
- **AND** the app SHALL speak that service has started

#### Scenario: Blind runner reaches completion and rating
- **WHEN** the active blind-runner order becomes `COMPLETED`
- **THEN** the app SHALL show a completion and optional rating experience
- **AND** the app SHALL allow the user to submit `POST /api/orders/{id}/review` with `CreateReviewRequest`
- **AND** the app SHALL allow the user to skip rating and return to the blind-runner home

### Requirement: Volunteer readiness requires certification, administrator approval, availability, WebSocket, and location
The iOS volunteer experience SHALL treat a volunteer as dispatch-ready only when profile requirements, certification/admin review requirements, manual availability opt-in, WebSocket connection, and recent location reporting are satisfied.

#### Scenario: Volunteer dispatch workbench is available after readiness gates
- **WHEN** a logged-in user has active role `VOLUNTEER`, a complete volunteer profile, `verificationStatus = approved`, `adminReviewStatus = approved` when provided by the backend, `wantsDispatch/isAvailable = true`, WebSocket online state, and recent location reporting
- **THEN** the app SHALL present the volunteer dispatch workbench as ready to receive backend dispatches
- **AND** the app SHALL load readiness, active orders, recent orders, points, and statistics from `GET /api/volunteer/dispatch-summary`

#### Scenario: Volunteer dispatch is blocked before readiness gates
- **WHEN** the volunteer is missing profile data, certification approval, administrator approval, manual availability opt-in, WebSocket connection, or location permission
- **THEN** the app SHALL present the not-ready reason
- **AND** the app SHALL block accepting dispatches from the UI and ViewModel action layer

### Requirement: Volunteer responds to timed system dispatch prompts
The iOS volunteer client SHALL handle backend `NEW_ORDER` WebSocket messages as timed dispatch prompts with accept and decline actions only.

#### Scenario: New order prompt appears
- **WHEN** `/ws/volunteer` receives `NEW_ORDER`
- **THEN** the app SHALL show a prompt using `dispatchTimeoutSeconds` with order time, start address, distance, priority, optional pace, optional guide dog flag, special notes, and optional coordinates
- **AND** the prompt SHALL include a map preview that shows both the volunteer current location and order start location when current location is available
- **AND** the prompt SHALL show only the order start location when current location is unavailable

#### Scenario: Volunteer accepts dispatch
- **WHEN** the volunteer taps accept before the prompt expires
- **THEN** the app SHALL report current location if available
- **AND** the app SHALL call `POST /api/orders/{id}/respond` with `action = ACCEPT`
- **AND** the app SHALL refresh `GET /api/orders/{id}` and `GET /api/volunteer/dispatch-summary` after success
- **AND** the app SHALL navigate to the accepted order service flow on success
- **AND** the service flow SHALL present a "go to start location" state for `PENDING_ACCEPT` and `DRIVER_EN_ROUTE`

#### Scenario: Volunteer navigates to the start location
- **WHEN** a volunteer order is `PENDING_ACCEPT` or `DRIVER_EN_ROUTE`
- **THEN** the app SHALL emphasize the order start location as the primary red marker on the service-flow map
- **AND** the app SHALL use the system user-location display and distance copy for current location instead of adding a separate green current-location marker on the service-flow map
- **AND** the app SHALL show the order start location and a location-unavailable hint when current location is unavailable
- **AND** the app SHALL offer walking navigation through installed external map apps, including AMap and Baidu when installed, and Apple Maps as the system fallback
- **AND** the app SHALL NOT add an in-app route-planning backend contract

#### Scenario: Client preserves backend status after dispatch acceptance
- **WHEN** the accepted order detail returns `IN_PROGRESS`, `REMATCHING`, or any other formal order status after `POST /api/orders/{id}/respond`
- **THEN** the app SHALL render the status returned by the backend and SHALL NOT synthesize a fake `PENDING_ACCEPT` state on the client
- **AND** release validation SHALL record a backend contract issue if accepting a dispatch skips directly to `IN_PROGRESS`
- **AND** release validation SHALL first check whether `REMATCHING` was caused by the volunteer explicitly cancelling after acceptance

#### Scenario: Volunteer declines or times out
- **WHEN** the volunteer taps decline or the prompt reaches zero
- **THEN** the app SHALL call `POST /api/orders/{id}/respond` with `action = DECLINE` when a prompt is still active
- **AND** the app SHALL dismiss the prompt without exposing a "later" or public-pool selection action

### Requirement: Service completion is allowed only from IN_PROGRESS
The iOS app SHALL enforce the canonical service completion path `DRIVER_ARRIVED -> IN_PROGRESS -> COMPLETED` and SHALL NOT allow `DRIVER_ARRIVED -> COMPLETED` from the client.

#### Scenario: Volunteer arrives and waits for service start
- **WHEN** a volunteer order is `DRIVER_ARRIVED`
- **THEN** the volunteer service UI SHALL show that the volunteer has arrived and is waiting for service to start
- **AND** the app SHALL continue listening or polling for `IN_PROGRESS`
- **AND** the app SHALL NOT show or execute a finish service action

#### Scenario: Volunteer completes service from IN_PROGRESS
- **WHEN** a volunteer order is `IN_PROGRESS`
- **THEN** the volunteer service UI SHALL show a finish service action
- **AND** the action SHALL require second confirmation
- **AND** confirmation SHALL call `POST /api/orders/{id}/finish`

#### Scenario: Client blocks invalid finish attempt
- **WHEN** code attempts to finish an order whose current status is not `IN_PROGRESS`
- **THEN** the ViewModel action layer SHALL block the request before calling `/api/orders/{id}/finish`
- **AND** the user SHALL receive a clear error or waiting-state message

### Requirement: Active order role switching remains blocked
The iOS app SHALL rely on `POST /api/user/role` for role switching and SHALL surface `ACTIVE_ORDER_ROLE_SWITCH_BLOCKED` when the user has an active service order.

#### Scenario: Role switch blocked with active order
- **WHEN** a user tries to switch roles while any order is `PENDING_ACCEPT`, `DRIVER_EN_ROUTE`, `DRIVER_ARRIVED`, or `IN_PROGRESS`
- **THEN** the backend may return `ACTIVE_ORDER_ROLE_SWITCH_BLOCKED`
- **AND** the app SHALL keep the current role and show a clear blocking message

#### Scenario: Role switch allowed without active order
- **WHEN** a logged-in user switches role without an active order
- **THEN** the app SHALL call `POST /api/user/role`
- **AND** the app SHALL store the returned token and route to the selected role flow

### Requirement: Emergency action remains placeholder for this change
The iOS app SHALL NOT launch a production emergency backend workflow as part of this change. Any emergency affordance kept in the UI SHALL be clearly treated as placeholder or deferred behavior until a dedicated safety change re-enables real emergency handling.

#### Scenario: Emergency placeholder is shown
- **WHEN** an order is in a state where a future emergency action is expected
- **THEN** the app MAY show a disabled or clearly placeholder emergency affordance
- **AND** the app SHALL NOT imply that a real emergency response has been triggered

#### Scenario: Real emergency backend flow is deferred
- **WHEN** the user interacts with the placeholder emergency affordance in this change
- **THEN** the app SHALL NOT silently call `POST /api/emergency/trigger` as a completed production safety workflow
- **AND** the app SHALL require a separate approved safety change before launching real emergency recording, GPS submission, volunteer response, notification, or escalation behavior

### Requirement: Mock and tests mirror the formal lifecycle
Mock API behavior and automated tests SHALL mirror the formal dispatch lifecycle used by cloud validation.

#### Scenario: Mock rejects direct completion from DRIVER_ARRIVED
- **WHEN** Mock receives `POST /api/orders/{id}/finish` for an order in `DRIVER_ARRIVED`
- **THEN** Mock SHALL return an invalid-status error
- **AND** Mock SHALL only allow finish when the order is `IN_PROGRESS`

#### Scenario: Tests cover complete formal lifecycle
- **WHEN** automated tests run for this change
- **THEN** they SHALL cover blind-runner booking through completion/rating, volunteer dispatch prompt response, strict `IN_PROGRESS` finish gating, admin review gating, role-switch blocking behavior, and emergency placeholder behavior
