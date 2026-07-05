## MODIFIED Requirements

### Requirement: Blind runner follows formal order lifecycle
The iOS blind-runner experience SHALL expose the formal order lifecycle from system dispatch through service completion and optional rating without skipping required lifecycle states.

#### Scenario: Blind runner waits through dispatch and arrival states
- **WHEN** an active blind-runner order is `PENDING_MATCH`, `PENDING_ACCEPT`, `DRIVER_EN_ROUTE`, or `DRIVER_ARRIVED`
- **THEN** the app SHALL show the status tracking experience
- **AND** `PENDING_ACCEPT` SHALL be displayed as "待出发"
- **AND** `PENDING_ACCEPT` TTS SHALL announce that a volunteer has accepted, include appointment time and start address when available, and tell the blind runner to go to or wait at the appointment start address
- **AND** `DRIVER_EN_ROUTE` SHALL be presented as the later departure update "志愿者已出发，正在前往出发地点"
- **AND** the app SHALL update status from `ORDER_STATUS_CHANGED` WebSocket events or 5-second polling of `GET /api/orders/{id}`
- **AND** the app SHALL provide a "重复当前状态" action that speaks the latest meaningful local status copy

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
- **AND** the blind runner SHALL NOT be shown a cancel action in `IN_PROGRESS`

#### Scenario: Blind runner reaches completion and rating
- **WHEN** the active blind-runner order becomes `COMPLETED`
- **THEN** the app SHALL show a completion and optional rating experience
- **AND** the app SHALL allow the user to submit `POST /api/orders/{id}/review` with `CreateReviewRequest`
- **AND** the app SHALL allow the user to skip rating and return to the blind-runner home

### Requirement: Blind runner state updates remain status driven
The iOS blind-runner order screens SHALL update from WebSocket notifications and REST polling without exposing backend dispatch rounds.

#### Scenario: Volunteer accepts dispatch
- **WHEN** the blind runner receives `ORDER_STATUS_CHANGED` or polling returns `PENDING_ACCEPT`
- **THEN** the app SHALL update the UI to show "待出发"
- **AND** TTS SHALL use local order-detail copy that says the volunteer has accepted, includes appointment time and start address when available, and tells the blind runner to go to or wait at the appointment start address
- **AND** the app SHALL NOT speak backend lifecycle `APP_NOTIFICATION` template text directly while an active order is present

#### Scenario: No volunteer is available
- **WHEN** WebSocket or polling returns `NO_VOLUNTEER`
- **THEN** the app SHALL show a no-volunteer terminal state
- **AND** TTS SHALL announce that no volunteer is currently available

#### Scenario: Volunteer location is available
- **WHEN** the order is `PENDING_ACCEPT`, `DRIVER_EN_ROUTE`, or `DRIVER_ARRIVED` and `/ws/blind` receives `VOLUNTEER_LOCATION_UPDATE`
- **THEN** the app SHALL calculate distance from the volunteer's latest coordinates to `order.startLatitude/startLongitude`
- **AND** the blind-runner UI and repeated status speech SHALL use "距出发地点约 X"
- **AND** the app SHALL NOT use "距您" for this distance
- **AND** the app SHALL hide distance when the order start coordinate or volunteer location is unavailable

### Requirement: Blind runner booking search is accessible
The iOS blind-runner booking flow SHALL support text and speech search for a start place without exposing raw coordinates in the normal user interface.

#### Scenario: Speech input searches start places
- **WHEN** the blind runner uses speech input in the start-place search field
- **AND** recognition finishes with non-empty recognized text
- **THEN** the app SHALL fill the search field with the recognized text
- **AND** the app SHALL automatically run the same AMap POI search as the search button
- **AND** the search button SHALL expose "语音识别中" while recognition is active
- **AND** the app SHALL NOT auto-search after recognition errors or no-speech silence timeouts

#### Scenario: Search results are announced without raw coordinates
- **WHEN** a start-place search returns one or more results
- **THEN** the app SHALL announce the result count and first place name to VoiceOver
- **AND** each selectable result SHALL expose the place name and address in its accessibility label
- **AND** raw latitude/longitude SHALL NOT be shown as normal text on the booking screen
- **AND** coordinates SHALL remain available for order creation and map annotations

### Requirement: Volunteer responds to timed system dispatch prompts
The iOS volunteer client SHALL handle backend `NEW_ORDER` WebSocket messages as timed dispatch prompts with accept and decline actions only.

#### Scenario: Volunteer accepts dispatch
- **WHEN** the volunteer taps accept on a dispatch prompt
- **THEN** the app SHALL report current location if available
- **AND** the app SHALL call `POST /api/orders/{id}/respond` with `action = ACCEPT`
- **AND** the app SHALL navigate to the accepted order detail or service flow on success
- **AND** `PENDING_ACCEPT` SHALL be displayed as "待出发"

#### Scenario: Volunteer navigates to the start location
- **WHEN** a volunteer order is `PENDING_ACCEPT` or `DRIVER_EN_ROUTE`
- **THEN** the app SHALL emphasize the order start location as the primary red marker on the service-flow map
- **AND** the service-flow map center SHALL remain anchored to the order start coordinate instead of recalculating a midpoint as the volunteer location changes
- **AND** the volunteer current location SHALL use the system user-location layer instead of a custom marker in the service-flow map
- **AND** map annotations SHALL be synced by stable annotation id so existing markers are updated in place rather than removed and re-added on every refresh
- **AND** pin drop animation SHALL NOT repeat during location reporting or polling updates
- **AND** the app SHALL offer walking navigation through installed external map apps, including AMap and Baidu when installed, and Apple Maps as the system fallback
- **AND** the app SHALL NOT add an in-app route-planning backend contract

### Requirement: Service completion is allowed only from IN_PROGRESS
The iOS app SHALL enforce the canonical volunteer-driven service path `DRIVER_ARRIVED -> IN_PROGRESS -> COMPLETED`, where the volunteer explicitly starts service before completion, and SHALL NOT allow `DRIVER_ARRIVED -> COMPLETED` from the client.

#### Scenario: Volunteer completes or cancels service from IN_PROGRESS
- **WHEN** a volunteer order is `IN_PROGRESS`
- **THEN** the volunteer service UI SHALL show a finish service action
- **AND** the finish action SHALL require second confirmation
- **AND** confirmation SHALL call `POST /api/orders/{id}/finish`
- **AND** the volunteer service UI SHALL also show a cancel action with second confirmation
- **AND** volunteer cancellation SHALL call `POST /api/orders/{id}/cancel`

### Requirement: Cancellation visibility is role-aware
The iOS app SHALL show order cancellation actions according to both the active role and the order status, while continuing to use the existing cancel endpoint.

#### Scenario: Blind-runner cancellation states
- **WHEN** the active role is `BLIND`
- **THEN** the app SHALL show "取消订单" only for `PENDING_MATCH`, `PENDING_ACCEPT`, and `REMATCHING`
- **AND** the action SHALL require second confirmation
- **AND** confirmation SHALL call `POST /api/orders/{id}/cancel`

#### Scenario: Volunteer cancellation states
- **WHEN** the active role is `VOLUNTEER`
- **THEN** the app SHALL show "取消订单" only for `PENDING_ACCEPT`, `DRIVER_EN_ROUTE`, `DRIVER_ARRIVED`, and `IN_PROGRESS`
- **AND** the action SHALL require second confirmation
- **AND** confirmation SHALL call `POST /api/orders/{id}/cancel`
- **AND** successful volunteer cancellation SHALL move the backend order to `REMATCHING`
- **AND** after a successful cancellation response the volunteer UI SHALL clear the local active service screen instead of fetching the order with a token that may no longer be a participant

#### Scenario: Blind runner cannot cancel travel, arrival, or in-service states
- **WHEN** a blind-runner order is `DRIVER_EN_ROUTE`, `DRIVER_ARRIVED`, or `IN_PROGRESS`
- **THEN** the blind-runner screens SHALL NOT show a cancel action
- **AND** safety concerns SHALL use the existing求助入口 or placeholder flow instead of cancellation
