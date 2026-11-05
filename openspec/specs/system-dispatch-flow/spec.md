# system-dispatch-flow Specification

## Purpose
Define how the iOS volunteer side receives work through backend system dispatch instead of a public order pool: the home screen renders the dispatch summary, the availability control only opts in or out of new dispatches, and an already accepted order stays usable regardless of that switch.
## Requirements
### Requirement: Volunteer home uses system dispatch summary
The iOS volunteer home screen SHALL use backend dispatch summary data as its primary source of truth and SHALL NOT present a public order pool or volunteer self-selection list as the primary experience.

#### Scenario: Volunteer home loads dispatch summary
- **WHEN** a volunteer opens the home screen
- **THEN** the app SHALL request `GET /api/volunteer/dispatch-summary`
- **AND** the app SHALL render dispatch readiness, not-available reasons, coverage radius, online/location state, active orders, recent orders, and service statistics from the response

#### Scenario: Public order pool is removed from primary home flow
- **WHEN** a volunteer is on the home screen
- **THEN** the app SHALL NOT show "nearby available orders" as the main call to action
- **AND** the app SHALL NOT provide a primary "view all available orders" entry for self-selecting blind-runner appointments

### Requirement: Volunteer availability controls dispatch opt-in
The iOS volunteer availability control SHALL update whether the volunteer wants to receive backend dispatches and SHALL NOT affect an already active accepted order.

#### Scenario: Volunteer turns dispatch on
- **WHEN** an approved volunteer enables the availability switch
- **THEN** the app SHALL update `wantsDispatch` through the backend availability contract
- **AND** the home screen SHALL refresh dispatch summary readiness

#### Scenario: Volunteer turns dispatch off with active order
- **WHEN** a volunteer disables availability while an active order exists
- **THEN** the app SHALL show availability as off for new dispatches
- **AND** the active order entry SHALL remain visible and usable

### Requirement: Volunteer receives timed dispatch prompts
The iOS volunteer client SHALL receive backend `NEW_ORDER` prompts through the app-lifetime realtime coordinator and retain accept/decline-only behavior.

#### Scenario: New order dispatch arrives
- **WHEN** `/ws/volunteer` receives a `NEW_ORDER` message
- **THEN** the app SHALL show a prompt whose reply deadline is the invite's `expiresAt` (the backend gives 60 or 15 minutes since #371; `dispatchTimeoutSeconds` is only the fallback)
- **AND** the prompt SHALL display order time, start address, distance, priority, optional pace, guide dog, notes, and optional start coordinates when present

#### Scenario: Dispatch arrives during navigation
- **WHEN** `/ws/volunteer` receives `NEW_ORDER` while volunteer home is not mounted
- **THEN** the coordinator SHALL retain and present the prompt until its `expiresAt`
- **AND** no public-order-pool or "later" action SHALL be introduced

#### Scenario: Volunteer accepts dispatch
- **WHEN** the volunteer taps accept on a dispatch prompt
- **THEN** the app SHALL report current location if available
- **AND** the app SHALL call `POST /api/orders/{id}/respond` with `action = ACCEPT`
- **AND** the app SHALL navigate to the accepted order detail or service flow on success

#### Scenario: Volunteer declines or times out
- **WHEN** the volunteer taps decline or the prompt timer reaches zero
- **THEN** the app SHALL call `POST /api/orders/{id}/respond` with `action = DECLINE` when appropriate
- **AND** the app SHALL dismiss the prompt without showing a "later" business action

### Requirement: Blind runner waiting describes system dispatch
The iOS blind-runner waiting experience SHALL describe `PENDING_MATCH` as backend system dispatch in progress.

#### Scenario: Blind runner submits appointment
- **WHEN** blind runner order creation succeeds and returns `PENDING_MATCH`
- **THEN** the app SHALL navigate to the order status screen
- **AND** the status text and TTS SHALL say the system is dispatching a suitable volunteer

#### Scenario: Blind runner repeats pending status
- **WHEN** the blind runner taps "重复当前状态" while the order is `PENDING_MATCH`
- **THEN** TTS SHALL replay system-dispatch waiting copy rather than public-order-pool copy

### Requirement: Blind runner state updates remain status driven
The iOS blind-runner order flow SHALL receive status and pre-service volunteer-location signals through the app-lifetime coordinator with REST fallback when documented.

#### Scenario: Volunteer accepts dispatch
- **WHEN** the blind runner receives `ORDER_STATUS_CHANGED` or polling returns `PENDING_ACCEPT`
- **THEN** the app SHALL update the UI to show a volunteer has accepted
- **AND** TTS SHALL announce the accepted volunteer state

#### Scenario: Volunteer status changes
- **WHEN** the coordinator receives a status event for the blind runner's order
- **THEN** the order ViewModel SHALL refresh canonical REST detail

#### Scenario: No volunteer is available
- **WHEN** WebSocket or polling returns `NO_VOLUNTEER`
- **THEN** the app SHALL show a no-volunteer terminal state
- **AND** TTS SHALL announce that no volunteer is currently available

#### Scenario: Volunteer location is available
- **WHEN** the order is `DRIVER_EN_ROUTE` or `DRIVER_ARRIVED`
- **THEN** the app SHALL display volunteer location from `VOLUNTEER_LOCATION_UPDATE`
- **AND** the app SHALL use `GET /api/blind/volunteer-location` as a fallback when WebSocket is unavailable

#### Scenario: Pre-service WebSocket location is unavailable
- **WHEN** an eligible pre-service order has disconnected or stale volunteer-location WebSocket data
- **THEN** the app SHALL use the typed `GET /api/blind/volunteer-location` fallback

### Requirement: Documentation matches system dispatch
Project documentation SHALL describe backend-controlled dispatch as the primary matching model and SHALL record remaining backend-owned behavior as contract dependencies.

#### Scenario: Documentation is updated
- **WHEN** this change is implemented
- **THEN** product, flow, page, data model, API, architecture, WebSocket, and UI handoff docs SHALL no longer describe public order pool self-selection as the primary volunteer flow
- **AND** docs SHALL state that expansion rings, volunteer ranking, simultaneous last-round dispatch, and citywide fallback notifications are backend-owned

### Requirement: Invite card shows the runner's escort fields and shared history
The volunteer invite card SHALL show the runner's vision level, tether preference, chat preference, route preference and the number of runs completed together, taken from the dispatch push when present, without inventing values for missing fields.

#### Scenario: Push carries the fields
- **WHEN** a `NEW_ORDER` push carries any of the five fields
- **THEN** the runner row SHALL be built from the push without waiting for `GET /api/orders/available`

#### Scenario: Profile fields are missing or have no preference
- **WHEN** a profile field is absent, or chat or route preference is `NO_PREFERENCE` or unrecognised
- **THEN** that item SHALL NOT be shown, and no default such as "全盲" SHALL be shown in its place

#### Scenario: Runs completed together
- **WHEN** `completedTogetherCount` is 0
- **THEN** the card SHALL say "第一次一起跑"
- **AND** when it is N > 0 the card SHALL say "一起跑过 N 次"
- **AND** when the key is missing no tag SHALL be shown

### Requirement: Invite shows the runner's masked name
The volunteer invite card and the invite-state order page SHALL show the runner's masked `blindName` from the dispatch push or the pending-invites list. The screen SHALL keep the mask (for example "李*"); VoiceOver labels SHALL drop the mask characters (for example "跑者李"). When the name is missing, blank, or only mask characters, no name SHALL be shown and none SHALL be invented.

#### Scenario: Push carries a masked name
- **WHEN** a `NEW_ORDER` push has `blindName = "李*"`
- **THEN** the invite card runner row SHALL show "跑者李*" with the avatar initial "李"
- **AND** its VoiceOver label SHALL start with "跑者李" and SHALL NOT contain "*"
- **AND** the invite-state order page SHALL show a runner row with value "李*" and VoiceOver label "跑者李"

#### Scenario: Name is missing
- **WHEN** the push has no `blindName`, or it is blank or only mask characters
- **THEN** the order page SHALL NOT show a runner row
- **AND** the invite card SHALL keep the "跑" avatar placeholder and the label "跑者"

### Requirement: Volunteer home reads upcoming orders from the dispatch summary
The volunteer home SHALL use `upcomingOrders` from `GET /api/volunteer/dispatch-summary` as the list of accepted orders that have not departed (`PENDING_ACCEPT` and `SCHEDULED_CONFIRMED`). An empty array SHALL mean there are none. A `null` value, or a missing summary, SHALL make the app fall back to `GET /api/orders/mine?role=VOLUNTEER&status=…` for both statuses. These orders SHALL NOT be merged into the active orders and SHALL NOT be registered for live location sharing.

#### Scenario: Summary carries upcoming orders
- **WHEN** the summary has `upcomingOrders` with two orders
- **THEN** the home SHALL list them by planned start time without calling `orders/mine`
- **AND** neither order SHALL become the active order or be registered for location sharing

#### Scenario: Empty array
- **WHEN** `upcomingOrders` is `[]`
- **THEN** the list SHALL be empty and the app SHALL NOT call `orders/mine`

#### Scenario: Null
- **WHEN** `upcomingOrders` is `null`
- **THEN** the app SHALL call `orders/mine` once for each of the two statuses and show what comes back

### Requirement: Volunteer statistics and service recognition are displayed
The iOS volunteer home screen SHALL display service statistics from dispatch summary, and SHALL derive every displayed figure from a backend-provided field. The app SHALL NOT synthesise a currency, balance, or reward figure that no backend field supplies.

#### Scenario: Summary contains completed count
- **WHEN** dispatch summary contains `totalCompleted`
- **THEN** the app SHALL display completed service count from `totalCompleted`
- **AND** the app SHALL NOT treat `totalAccepted` as completed service count

#### Scenario: A reward field is absent
- **WHEN** dispatch summary omits a rewards figure such as `pointsBalance`, or a recent order omits `pointsDelta`
- **THEN** the app SHALL omit that figure entirely
- **AND** the app SHALL NOT substitute a value derived from `totalCompleted`
- **AND** the app SHALL NOT present a rewards catalogue, balance, or redemption path that no backend endpoint serves

#### Scenario: Volunteer opens service recognition
- **WHEN** the volunteer opens the service recognition screen
- **THEN** the screen SHALL read its data from `GET /api/volunteer/achievements`
- **AND** the screen SHALL NOT synthesise recognition tiers that no backend field supplies
- **AND** the screen SHALL show the national star level and the platform badges as two separate sections
- **AND** each badge SHALL be distinguishable by its name and its symbol, not by colour alone

#### Scenario: National star level is shown separately from platform badges
- **WHEN** the recognition screen renders the national star level
- **THEN** the thresholds SHALL be those of GB/T 40143—2021, namely 100, 300, 600, 1000 and 1500 accumulated service hours
- **AND** the screen SHALL NOT merge the star level with the platform badges, because the highest platform hour badge is 50 hours and cannot reach the 100-hour first star
- **AND** the remaining hours to the next star SHALL be available as readable text, not only as the geometry of a progress bar

#### Scenario: Badge list semantics
- **WHEN** the response contains `badges`
- **THEN** the app SHALL treat every entry as unlocked, because the contract states that locked badges do not appear in the list
- **AND** the app SHALL NOT read an `unlocked` flag to decide whether an entry is unlocked
- **AND** an unrecognised badge `code` SHALL still render with its `name` and a fallback symbol rather than failing the whole response

#### Scenario: Progress toward the next badge is not available
- **WHEN** the response omits `nextBadge`, which the contract uses to mean every badge is unlocked
- **THEN** the screen SHALL omit the next-badge section entirely
- **AND** the screen SHALL NOT derive that progress from client-side badge thresholds

#### Scenario: Next-badge progress carries a code-dependent unit
- **WHEN** the screen renders `nextBadge.current` and `nextBadge.target`
- **THEN** a `FIRST_RUN` or `RUNS_*` code SHALL be rendered as a count of runs
- **AND** an `HOURS_*` code SHALL be converted from minutes to whole hours before display, because the backend sends minutes for those codes
- **AND** a `HIGH_RATED` code SHALL be rendered as a count of ratings
- **AND** an unrecognised code SHALL hide the progress bar and its text while still showing the badge name

#### Scenario: Next-badge copy does not promise an unlock
- **WHEN** the screen renders next-badge progress for `HIGH_RATED`
- **THEN** the copy SHALL NOT state how many more units unlock the badge, because `HIGH_RATED` also requires an average rating and its progress bar can be full while the badge stays locked

#### Scenario: Achievements request fails or fields are absent
- **WHEN** the request fails, or `totalCompleted` and `totalServiceMinutes` are absent
- **THEN** the screen SHALL treat the missing figures as zero and SHALL NOT fail to render
- **AND** a failed request SHALL offer a retry

#### Scenario: Recognition copy is not a credential
- **WHEN** the recognition screen renders any of its own copy
- **THEN** that copy SHALL NOT use the words 证明, 证书 or 已认证 for service hours or star level, because a verifiable volunteer service record must be issued through the volunteer service information system (民政部令第 67 号) and this platform has no data integration with it
- **AND** the screen SHALL state where an external declaration is actually filed

### Requirement: Invite APNs lock-screen actions
The app SHALL register the `INVITE` category with `ACCEPT_INVITE` and `DECLINE_INVITE`, and the `INVITE_INTRO_CALL` category with only `DECLINE_INVITE`. Both actions SHALL require authentication and SHALL bring the app to the foreground. The app SHALL reply only to the matching invite (same `inviteId`, otherwise same `expiresAt`) that is still awaiting a reply in the current account's queue, through the same call as the invite card's button.

#### Scenario: Accept from the lock screen
- **WHEN** the volunteer taps "接下这次陪跑" on an invite notification
- **THEN** after the invite is in the in-app queue the app SHALL open that invite card and respond through the same call as the card's accept button
- **AND** when the next pending-invites snapshot does not contain the invite, the app SHALL say "这个邀请已失效，不需要再回复了"

#### Scenario: Decline from the lock screen
- **WHEN** the volunteer taps "这次去不了" on an invite notification and the invite is in the queue
- **THEN** the app SHALL decline it through the card's decline call, with the same 5-second undo

#### Scenario: Notification for an older invite of the same order
- **WHEN** the queue holds a newer invite for the same order with a different `expiresAt`
- **THEN** the lock-screen action SHALL NOT reply to the newer invite

#### Scenario: Stale notifications are removed
- **WHEN** an invite is withdrawn, replied to in the app, or missing from a snapshot it predates
- **THEN** the delivered notifications for that invite SHALL be removed, and those of a newer invite for the same order SHALL stay

#### Scenario: New invite APNs while the app is in the foreground
- **WHEN** a `NEW_ORDER` APNs arrives while the app is in the foreground
- **THEN** the system banner SHALL NOT be shown and nothing SHALL be spoken for it
- **AND** the app SHALL reconcile the pending-invites list so the invite appears once in the app

### Requirement: Consecutive declines follow the backend count
The availability prompt SHALL use `consecutiveDeclineCount` from `GET /api/volunteer/pending-invites`. The client SHALL remember the count at which it last asked and SHALL ask again only after the count rises by 3 more; when the backend count drops below that value, the remembered value SHALL reset.

#### Scenario: Asking again
- **WHEN** the prompt was shown at count 3 and the backend later reports 5
- **THEN** the prompt SHALL NOT be shown
- **AND** when the backend reports 6 the prompt SHALL be shown

