## MODIFIED Requirements

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

## ADDED Requirements

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
