# formal-dispatch-service-flow Specification

## Purpose
Define the iOS formal dispatch and service lifecycle for blind-runner booking, volunteer readiness and dispatch response, canonical order-status routing, strict service completion gates, hidden emergency UI behavior for the current release, and Mock/test coverage.
## Requirements
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

### Requirement: Blind runner state updates remain status driven
The iOS blind-runner order screens SHALL update from app-lifetime WebSocket routing and REST polling without exposing backend dispatch rounds.

#### Scenario: Volunteer accepts dispatch
- **WHEN** the coordinator routes `ORDER_STATUS_CHANGED` or polling returns `PENDING_ACCEPT`
- **THEN** the app SHALL refresh and show the canonical "待出发" state
- **AND** TTS SHALL use local order-detail copy rather than duplicate lifecycle template speech

#### Scenario: No volunteer is available
- **WHEN** WebSocket or polling returns `NO_VOLUNTEER`
- **THEN** the app SHALL show and announce a no-volunteer terminal state

#### Scenario: Volunteer location is available
- **WHEN** the order is `PENDING_ACCEPT`, `DRIVER_EN_ROUTE`, or `DRIVER_ARRIVED` and the coordinator routes a fresh `VOLUNTEER_LOCATION_UPDATE` from `/ws/blind`
- **THEN** the app SHALL calculate distance from the volunteer's latest coordinates to `order.startLatitude/startLongitude`
- **AND** the blind-runner UI and repeated status speech SHALL use "距出发地点约 X"
- **AND** the app SHALL NOT use "距您" for this distance
- **AND** the app SHALL hide distance when the order start coordinate or volunteer location is unavailable
- **AND** service-session peer presentation SHALL remain owned by `enable-live-escort-location-and-track-summary`

#### Scenario: REST fallback is used before service
- **WHEN** an eligible pre-service order has disconnected or stale WebSocket volunteer location
- **THEN** the app SHALL use the typed `GET /api/blind/volunteer-location` fallback according to its freshness/no-data contract

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

#### Scenario: New order prompt appears
- **WHEN** `/ws/volunteer` receives `NEW_ORDER`
- **THEN** the app SHALL show a prompt whose reply deadline comes from `expiresAt` (falling back to the send time plus `dispatchTimeoutSeconds` only when `expiresAt` is absent) with order time, start address, distance, priority, optional pace, optional guide dog flag, special notes, and optional coordinates
- **AND** the prompt SHALL include a map preview that shows both the volunteer current location and order start location when current location is available
- **AND** the prompt SHALL show only the order start location when current location is unavailable

#### Scenario: Volunteer accepts dispatch
- **WHEN** the volunteer taps accept before the prompt expires
- **THEN** the app SHALL report current location if available
- **AND** the app SHALL call `POST /api/orders/{id}/respond` with `action = ACCEPT`
- **AND** the app SHALL refresh `GET /api/orders/{id}` and `GET /api/volunteer/dispatch-summary` after success
- **AND** the app SHALL navigate to the accepted order service flow on success
- **AND** `PENDING_ACCEPT` SHALL be displayed as "待出发"
- **AND** the service flow SHALL present a "go to start location" state for `PENDING_ACCEPT` and `DRIVER_EN_ROUTE`

#### Scenario: Volunteer navigates to the start location
- **WHEN** a volunteer order is `PENDING_ACCEPT` or `DRIVER_EN_ROUTE`
- **THEN** the app SHALL emphasize the order start location as the primary red marker on the service-flow map
- **AND** the service-flow map center SHALL remain anchored to the order start coordinate instead of recalculating a midpoint as the volunteer location changes
- **AND** the app SHALL use the system user-location display and distance copy for current location instead of adding a separate green current-location marker on the service-flow map
- **AND** map annotations SHALL be synced by stable annotation id so existing markers are updated in place rather than removed and re-added on every refresh
- **AND** pin drop animation SHALL NOT repeat during location reporting or polling updates
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
The iOS app SHALL enforce the canonical service path `DRIVER_ARRIVED -> IN_PROGRESS -> COMPLETED`, where either participant explicitly starts service before completion, and SHALL NOT allow `DRIVER_ARRIVED -> COMPLETED` from the client.

#### Scenario: Volunteer starts service after arrival
- **WHEN** a volunteer order is `DRIVER_ARRIVED`
- **THEN** the volunteer service UI SHALL show a "开始跑步" action
- **AND** tapping the action SHALL call `POST /api/orders/{id}/start-service`
- **AND** a successful response SHALL move the order to `IN_PROGRESS`
- **AND** the blind-runner UI SHALL receive `IN_PROGRESS` through WebSocket or polling

#### Scenario: Blind runner starts service after arrival
- **WHEN** a blind-runner order is `DRIVER_ARRIVED`
- **THEN** the blind-runner order page primary action SHALL be "开始跑步"
- **AND** tapping the action SHALL call `POST /api/orders/{id}/start-service` with the blind-runner token
- **AND** a successful response SHALL reload the order so the existing three-second countdown starts from the `DRIVER_ARRIVED -> IN_PROGRESS` transition
- **AND** the app SHALL NOT call `POST /api/orders/{id}/confirm-start` separately, because the backend records the blind runner's consent when the blind runner starts service

#### Scenario: Start is locked until the server-given time
- **WHEN** the order detail carries `earliestServiceStartAt` and the current time is before it
- **THEN** the "开始跑步" action SHALL stay in place but be disabled
- **AND** its accessibility hint and the subtitle SHALL state the clock time from which it can be pressed
- **AND** it SHALL become enabled after that time without user action

#### Scenario: Blind runner starts too early
- **WHEN** `earliestServiceStartAt` is absent and the blind runner taps "开始跑步" and the backend returns 409 `SERVICE_START_TOO_EARLY`
- **THEN** the app SHALL show and speak the mapped error copy
- **AND** the app SHALL NOT compute an earliest start time from `plannedStartTime` on the client

#### Scenario: The other participant already started
- **WHEN** the blind runner taps "开始跑步" after the volunteer already started service
- **THEN** a successful response or a reload SHALL show the in-service experience without an error

#### Scenario: Volunteer completes service from IN_PROGRESS
- **WHEN** a volunteer order is `IN_PROGRESS`
- **THEN** the volunteer service UI SHALL show a finish service action
- **AND** the action SHALL require second confirmation
- **AND** confirmation SHALL call `POST /api/orders/{id}/finish`
- **AND** the volunteer service UI SHALL also show a cancel action with second confirmation
- **AND** volunteer cancellation SHALL call `POST /api/orders/{id}/cancel`

#### Scenario: Client blocks invalid finish attempt
- **WHEN** code attempts to finish an order whose current status is not `IN_PROGRESS`
- **THEN** the ViewModel action layer SHALL block the request before calling `/api/orders/{id}/finish`
- **AND** the user SHALL receive a clear error or waiting-state message

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
- **AND** current-release safety concerns SHALL NOT expose emergency UI and SHALL remain covered by the hidden/deferred safety contract

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

### Requirement: Emergency action is hidden for this release
The iOS app SHALL NOT launch a production emergency backend workflow as part of this release. Emergency backend contracts may be probed by scripts, but blind-runner and volunteer UI SHALL hide emergency affordances until a dedicated safety change re-enables real emergency handling.

#### Scenario: Emergency affordance is hidden
- **WHEN** an order is in a state where a future emergency action is expected
- **THEN** the app SHALL NOT show "紧急求助" or "一键求助"
- **AND** the app SHALL NOT show deferred emergency copy
- **AND** the app SHALL NOT imply that a real emergency response has been triggered

#### Scenario: Real emergency backend flow remains contract-only
- **WHEN** a script probes `POST /api/emergency/trigger`
- **THEN** the result SHALL be treated as backend contract validation, not as iOS UI emergency enablement
- **AND** the app SHALL require a separate approved safety change before launching real emergency recording, GPS submission, volunteer response, notification, or escalation behavior

### Requirement: Mock and tests mirror the formal lifecycle
Mock API behavior and automated tests SHALL mirror the formal dispatch lifecycle used by cloud validation.

#### Scenario: Mock starts service from DRIVER_ARRIVED
- **WHEN** Mock receives `POST /api/orders/{id}/start-service` for an order in `DRIVER_ARRIVED`
- **THEN** Mock SHALL move the order to `IN_PROGRESS`
- **AND** Mock SHALL return success without changing the order when it is already `IN_PROGRESS`, because the backend returns 200 to whichever participant presses second
- **AND** Mock SHALL reject the same endpoint for other order statuses with `INVALID_ORDER_STATUS`

#### Scenario: Mock rejects direct completion from DRIVER_ARRIVED
- **WHEN** Mock receives `POST /api/orders/{id}/finish` for an order in `DRIVER_ARRIVED`
- **THEN** Mock SHALL return an invalid-status error
- **AND** Mock SHALL only allow finish when the order is `IN_PROGRESS`

### Requirement: Realtime feature events survive navigation
Order, dispatch, peer-location, separation-alert, and safety events SHALL be routed independently of individual screen lifetimes.

#### Scenario: Relevant feature screen is not mounted
- **WHEN** a typed event for the active user/order arrives during navigation
- **THEN** the app-lifetime coordinator SHALL retain or route the actionable signal
- **AND** the destination feature SHALL reconcile with authoritative backend state when presented

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

### Requirement: Invite deadlines follow the server and read in minutes
The volunteer app SHALL take each invite's reply deadline from `NEW_ORDER.expiresAt` and SHALL fall back to the send time plus `dispatchTimeoutSeconds` only when `expiresAt` is absent. The reply countdown SHALL read in minutes (rounded up) when at least one minute remains and in seconds during the last minute. The countdown SHALL turn urgent when the displayed minutes are fewer than 15.

#### Scenario: Long invite window
- **WHEN** an invite has 3599 seconds left
- **THEN** the countdown SHALL read "还剩 60 分钟回复"

#### Scenario: Urgency threshold
- **WHEN** an invite has 840 seconds left (displayed as 14 minutes)
- **THEN** the countdown SHALL be urgent
- **AND** with 841 seconds left (displayed as 15 minutes) it SHALL NOT be urgent

### Requirement: Invites are identified by inviteId
The volunteer app SHALL treat `inviteId` as the identity of an invite. A new invite for an order whose previous invite was invalidated SHALL replace the invalidated card. A repeated delivery of the same invite SHALL NOT create a second card. When either side lacks `inviteId`, the app SHALL fall back to `orderId`.

#### Scenario: Re-invited after a withdrawal
- **WHEN** an invite for order 10 was withdrawn and a new `NEW_ORDER` for order 10 arrives with a different `inviteId`
- **THEN** the new invite SHALL replace the invalidated card and await a reply

### Requirement: Withdrawn and rejected invites are invalidated in place
When an invite is withdrawn (`INVITE_WITHDRAWN`), missing from the pending-invites snapshot, or rejected by `POST /respond` with 409 `ORDER_ALREADY_ACCEPTED` or `ORDER_DISPATCH_MISMATCH`, the app SHALL NOT keep an actionable accept button for it.

#### Scenario: The invite on screen is withdrawn
- **WHEN** the invite card on screen receives `INVITE_WITHDRAWN` with reason `TAKEN`
- **THEN** the card SHALL turn into "这个邀请已失效" with the line "已有其他陪跑员接下"
- **AND** the app SHALL speak that title and line

#### Scenario: An invite off screen is withdrawn
- **WHEN** an invite that is not on screen is withdrawn
- **THEN** it SHALL be removed without showing a result card

#### Scenario: A late withdrawal for an older invite
- **WHEN** `INVITE_WITHDRAWN` names an `inviteId` that differs from the invite currently held for that order
- **THEN** the current invite SHALL stay

#### Scenario: Accept is rejected because someone else took it
- **WHEN** the volunteer taps accept and the backend returns 409 `ORDER_ALREADY_ACCEPTED`
- **THEN** that card SHALL turn into "这个邀请已失效" with the line "已有其他陪跑员接下" and the app SHALL speak it, whether or not the card was on screen

### Requirement: Pending invites are reconciled with the server
The volunteer app SHALL request `GET /api/volunteer/pending-invites` on cold start, when returning to the foreground, and after the WebSocket reconnects. Invites in the snapshot that the app does not hold SHALL be added. Invites the app held before the request was sent that are absent from the snapshot SHALL be invalidated. Invites received after the request was sent SHALL be kept.

#### Scenario: Taken while offline
- **WHEN** the app held an invite before the request and the snapshot does not contain it
- **THEN** the invite SHALL be invalidated with the line "不需要再回复了"

#### Scenario: Response without the invites key
- **WHEN** the response omits `invites`
- **THEN** the app SHALL NOT invalidate any invite

### Requirement: Blind-runner arrival copy names the start action
In `DRIVER_ARRIVED`, blind-runner status copy SHALL NOT tell the blind runner to wait for the volunteer to start service. Copy shown on the order page SHALL point to the "开始跑步" action below; copy spoken or shown outside the order page SHALL NOT refer to an on-screen position.

#### Scenario: Order page arrival subtitle
- **WHEN** the blind-runner order page renders `DRIVER_ARRIVED`
- **THEN** the subtitle SHALL include "见面后，轻点下方开始跑步"

#### Scenario: Arrival announcement outside the order page
- **WHEN** the home screen or the voice status query describes `DRIVER_ARRIVED`
- **THEN** the copy SHALL name the "开始跑步" action without referring to an on-screen position
- **AND** the copy SHALL NOT contain "轻点下方" or "等待志愿者开始服务"
- **AND** the copy SHALL stay true when the volunteer page speaks it, so it SHALL NOT claim the volunteer can start without the runner

#### Scenario: Calling the volunteer remains reachable
- **WHEN** the blind-runner order page renders `DRIVER_ARRIVED`
- **THEN** the "遇到问题" row SHALL open the safety hub, which offers calling the volunteer

