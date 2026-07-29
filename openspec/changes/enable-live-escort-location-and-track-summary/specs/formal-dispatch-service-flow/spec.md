## MODIFIED Requirements

### Requirement: Blind runner state updates remain status driven
The blind-runner order experience SHALL remain driven by canonical order status while presenting the associated volunteer's fresh live location during eligible states and the completed run summary after `COMPLETED`.

#### Scenario: Volunteer is travelling, arrived, or running
- **WHEN** the order is `DRIVER_EN_ROUTE`, `DRIVER_ARRIVED`, or `IN_PROGRESS`
- **THEN** the blind-runner flow MAY present the associated volunteer's fresh map marker from routed WebSocket data
- **AND** it SHALL keep status, primary action, and repeat-status information accessible ahead of auxiliary map inspection

#### Scenario: Order completes
- **WHEN** canonical order detail becomes `COMPLETED`
- **THEN** the blind-runner completion flow SHALL offer the track summary with blind route, distance, duration, and pace

### Requirement: Volunteer service flow presents associated blind-runner location
The volunteer service flow SHALL present the associated blind runner's fresh location during `DRIVER_EN_ROUTE`, `DRIVER_ARRIVED`, and `IN_PROGRESS` without changing lifecycle actions.

#### Scenario: Blind-runner location is fresh
- **WHEN** a matching `BLIND_LOCATION_UPDATE` is routed during an eligible order state
- **THEN** the volunteer map SHALL update the blind-runner marker
- **AND** en-route, arrived, start-service, finish, and cancel permissions SHALL remain based only on canonical order status

### Requirement: Committed role homes render one live AMap without blocking local interaction
Debug, DemoRelease, and Production SHALL mount one live AMap for the committed blind-runner or volunteer home, and SHALL NOT replace it with a release-only product placeholder.

#### Scenario: A role home is committed
- **WHEN** root hydration commits the blind-runner or volunteer home
- **THEN** exactly one home map container SHALL be mounted for that role
- **AND** refresh, WebSocket recovery, and order-state changes SHALL update map inputs without replacing the map root
- **AND** scrolling, navigation, speech, dispatch controls, and retry SHALL remain usable while network requests are pending

#### Scenario: Volunteer home top content changes
- **WHEN** the status block or current-order card changes the volunteer-home top content
- **THEN** the demand-panel boundary SHALL be derived from stable safe-area and order-presence inputs
- **AND** child layout measurement SHALL NOT be written back into the same parent layout graph
- **AND** repeated SwiftUI evaluation SHALL NOT form an AttributeGraph refresh loop

#### Scenario: SwiftUI rebuilds a current-value announcement subscription
- **WHEN** TTS or another observed service publication causes the root view to rebuild while the same foreground notification or escort-health value remains current
- **THEN** the reconstructed publisher subscription SHALL NOT announce that same identity again
- **AND** announcement state SHALL NOT form a render, resubscribe, and TTS feedback loop

#### Scenario: The role home is left
- **WHEN** the account changes role, logs out, or navigates to another root route
- **THEN** the prior home map SHALL be unmounted before another role home map is committed

#### Scenario: AMap configuration is unavailable
- **WHEN** the local AMap Key is missing or a UI test explicitly disables map rendering
- **THEN** the map region MAY show the configuration-failure fallback
- **AND** the rest of the home SHALL remain interactive

### Requirement: Volunteer state commands do not wait on authoritative confirmation
The volunteer service flow SHALL submit each state-changing POST separately from WebSocket or REST confirmation and SHALL keep the rest of the page interactive while confirmation is pending.

#### Scenario: State command succeeds but confirmation query never returns
- **WHEN** a volunteer transition POST succeeds and all following detail queries remain suspended
- **THEN** the POST spinner SHALL end and the flow SHALL show `awaitingConfirmation`
- **AND** a duplicate submission of the same transition SHALL be blocked
- **AND** map presentation, scrolling, external navigation, cancellation entry, and back navigation SHALL remain usable
- **AND** after 20 seconds the flow SHALL show `confirmationDelayed` with a read-only status retry that does not repeat the POST

#### Scenario: En-route status is confirmed while location side effects hang
- **WHEN** a valid associated `DRIVER_EN_ROUTE` event arrives and detail, location, or WebSocket-send work does not return
- **THEN** the matching volunteer and blind-runner pages SHALL commit the new status within the current UI cycle
- **AND** escort-session, map, location, and detail work SHALL continue independently
- **AND** scrolling, back navigation, external navigation, cancellation, and repeat-status SHALL remain usable

#### Scenario: The same status is observed by home and detail flows
- **WHEN** multiple mounted flows submit the same order and status to the live escort coordinator
- **THEN** they SHALL share the reconciled status
- **AND** exactly one escort-session reconcile SHALL be scheduled for that order/status

#### Scenario: State command has an uncertain transport result
- **WHEN** the POST reaches its application deadline or fails with a transport/decoding error
- **THEN** the flow SHALL treat the outcome as unconfirmed rather than failed
- **AND** only WebSocket or bounded REST detail confirmation SHALL commit the target status

#### Scenario: State command is explicitly rejected
- **WHEN** the backend returns an explicit 4xx or 5xx contract error
- **THEN** the original action SHALL become retryable and the error SHALL be shown
- **AND** a 401 response SHALL use the existing session-expiration flow

#### Scenario: Arrival is submitted while confirmation or location work hangs
- **WHEN** the volunteer submits `/arrived` and its POST result is uncertain, its detail confirmation hangs, or peer-location work remains pending
- **THEN** only the arrival transition control SHALL show submission or confirmation state
- **AND** the spinner SHALL end at the existing command deadline
- **AND** scrolling, back navigation, external navigation, cancellation entry, and the live map SHALL remain usable
- **AND** a valid `DRIVER_EN_ROUTE` to `DRIVER_ARRIVED` WebSocket event SHALL advance both role UIs without waiting for those side effects

### Requirement: Service completion remains separate from track availability
`POST /api/orders/{id}/finish` SHALL remain the only volunteer action that moves `IN_PROGRESS` to `COMPLETED`; track fetching and summary rendering SHALL NOT alter that transition.

#### Scenario: Track endpoint is temporarily unavailable after finish
- **WHEN** order completion succeeds but track loading fails or is delayed
- **THEN** the order SHALL remain `COMPLETED`
- **AND** the summary SHALL show retry/unavailable state without retrying finish
