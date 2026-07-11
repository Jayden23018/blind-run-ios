## MODIFIED Requirements

### Requirement: Blind runner profile and booking gate
The iOS app SHALL require a logged-in blind-runner user to select the blind role, complete the blind-runner profile, store at least one emergency contact, grant location access, choose a start location through the voice-first guided booking flow, and choose an appointment time at least 30 minutes in the future before submitting a booking.

#### Scenario: Blind runner can submit booking after required gates
- **WHEN** a logged-in user has active role `BLIND`, a complete blind-runner profile, at least one emergency contact, location permission, a start location, and an appointment time at least 30 minutes away
- **THEN** the app SHALL allow booking submission through `POST /api/orders`
- **AND** the booking UI SHALL guide the user through start point, appointment time, optional running needs, and review before submission
- **AND** the app SHALL navigate to the order status flow when the backend returns an order ID

#### Scenario: Booking is blocked without required gates
- **WHEN** the blind-runner user lacks profile completion, emergency contact, location permission, start location, or a valid appointment time
- **THEN** the app SHALL block `POST /api/orders`
- **AND** the app SHALL show and speak a clear error prompt
- **AND** the guided booking repeat-status action SHALL include the blocking reason when the user asks to repeat the current state

#### Scenario: Booking keeps map and coordinate contracts
- **WHEN** the blind-runner user confirms a start point through current location or AMap POI search
- **THEN** the app SHALL preserve coordinates for `CreateOrderRequest`, map annotations, and release validation
- **AND** visual map confirmation SHALL remain auxiliary to textual and spoken start-point confirmation
- **AND** no new backend endpoint or draft-booking contract SHALL be required

### Requirement: Blind runner follows formal order lifecycle
The iOS blind-runner experience SHALL expose the formal order lifecycle from system dispatch through service completion and optional rating without skipping required lifecycle states, while presenting status and next action before auxiliary visual map content.

#### Scenario: Blind runner waits through dispatch and arrival states
- **WHEN** an active blind-runner order is `PENDING_MATCH`, `PENDING_ACCEPT`, `DRIVER_EN_ROUTE`, or `DRIVER_ARRIVED`
- **THEN** the app SHALL show the status tracking experience
- **AND** the status tracking experience SHALL present current status, appointment time, start address, and next expected action before auxiliary map content in VoiceOver traversal
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
- **AND** the app SHALL continue to hide blind-runner cancellation in `IN_PROGRESS`

#### Scenario: Blind runner reaches completion and rating
- **WHEN** the active blind-runner order becomes `COMPLETED`
- **THEN** the app SHALL show a completion and optional rating experience
- **AND** the app SHALL allow the user to submit `POST /api/orders/{id}/review` with `CreateReviewRequest`
- **AND** the app SHALL allow the user to skip rating and return to the blind-runner home
- **AND** completion and rating controls SHALL remain reachable through large, clearly labeled VoiceOver-accessible actions
