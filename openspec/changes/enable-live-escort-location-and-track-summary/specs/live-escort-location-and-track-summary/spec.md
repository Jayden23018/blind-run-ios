## ADDED Requirements

### Requirement: Both roles maintain the documented live escort cadence
The iOS app SHALL send `PING` every 30 seconds on both authenticated role WebSockets and SHALL send the latest valid participant location every five seconds during an owned eligible escort session.

#### Scenario: Eligible service session starts
- **WHEN** an associated order reaches `DRIVER_EN_ROUTE`, `DRIVER_ARRIVED`, or `IN_PROGRESS`
- **THEN** the active role SHALL send one immediate `LOCATION_UPDATE`
- **AND** it SHALL continue sending the latest valid location every five seconds while the state remains eligible

#### Scenario: Heartbeat and location timers coincide
- **WHEN** a 30-second `PING` and five-second `LOCATION_UPDATE` become ready inside the transport minimum-send window
- **THEN** both messages SHALL be serialized with at least 500 ms between sends
- **AND** neither message SHALL be silently dropped

#### Scenario: WebSocket reconnects during an eligible session
- **WHEN** the role WebSocket reconnects
- **THEN** heartbeat health SHALL restart
- **AND** the latest valid location SHALL be sent immediately before normal five-second cadence resumes

#### Scenario: Escort session becomes ineligible
- **WHEN** the order completes, cancels, rematches, becomes no-volunteer, loses participant association, or the authenticated session ends
- **THEN** the five-second session cadence SHALL stop and peer-session state SHALL be cleared

### Requirement: Active runs continue location capture while locked or backgrounded
The iOS app SHALL continue real device location capture and reporting while an owned order is `IN_PROGRESS` and the app is locked or backgrounded, subject to disclosed iOS permission/runtime limitations.

#### Scenario: Device locks during a run
- **WHEN** location permission remains authorized, the app process remains eligible for background location, and the order is `IN_PROGRESS`
- **THEN** location capture and five-second reporting SHALL continue
- **AND** returning to the app SHALL show the run remained active without synthesizing missing points

#### Scenario: Run leaves IN_PROGRESS
- **WHEN** the order leaves `IN_PROGRESS`
- **THEN** enhanced background location behavior SHALL stop promptly
- **AND** the location manager SHALL return to its normal non-run policy

#### Scenario: Location becomes unavailable
- **WHEN** permission is revoked or no valid real location is available
- **THEN** cloud sessions SHALL NOT send demo coordinates
- **AND** the app SHALL present visible and spoken degraded-recording guidance

### Requirement: Cloud coordinates use one GCJ-02 boundary
All outbound service locations SHALL be normalized exactly once to the frozen backend GCJ-02 contract, and all documented inbound peer and track coordinates SHALL be interpreted consistently for AMap display and statistics.

#### Scenario: Device sample is uploaded
- **WHEN** a real device sample is selected for `LOCATION_UPDATE`
- **THEN** the centralized network boundary SHALL produce one GCJ-02 coordinate
- **AND** feature code SHALL NOT apply another conversion

#### Scenario: Inbound track is rendered
- **WHEN** the backend returns GCJ-02 track points
- **THEN** AMap SHALL render those points without a second conversion

### Requirement: Associated participants receive fresh peer positions
The iOS app SHALL present fresh peer positions only to the blind runner and volunteer associated with the same eligible order.

#### Scenario: Volunteer location reaches blind runner
- **WHEN** `/ws/blind` receives a fresh matching `VOLUNTEER_LOCATION_UPDATE` during `DRIVER_EN_ROUTE`, `DRIVER_ARRIVED`, or `IN_PROGRESS`
- **THEN** the blind-runner map SHALL update the associated volunteer marker

#### Scenario: Blind-runner location reaches volunteer
- **WHEN** `/ws/volunteer` receives a fresh matching `BLIND_LOCATION_UPDATE` during `DRIVER_EN_ROUTE`, `DRIVER_ARRIVED`, or `IN_PROGRESS`
- **THEN** the volunteer map SHALL update the associated blind-runner marker

#### Scenario: Peer sample is stale or unrelated
- **WHEN** a peer sample is stale, invalid, or references another order
- **THEN** it SHALL NOT update the visible marker
- **AND** raw coordinates SHALL NOT be shown or logged

### Requirement: Separation alerts are immediate and status neutral
The app SHALL present a backend `ESCORT_DISTANCE_ALERT` as a high-priority visible, VoiceOver, and TTS warning without changing canonical order or emergency state.

#### Scenario: Separation alert arrives
- **WHEN** the backend emits a typed separation alert for the active order
- **THEN** both affected role experiences SHALL present the documented safe text immediately
- **AND** repeated delivery of the same event identity SHALL be deduplicated
- **AND** `RunOrderStatus` SHALL remain unchanged

### Requirement: Completed summary uses the blind track as the run route
After an associated order is `COMPLETED`, the app SHALL fetch the typed track response and present the blind-runner track and statistics as the primary run summary.

#### Scenario: Completed track is available
- **WHEN** `GET /api/orders/{id}/track` returns blind track points and statistics
- **THEN** the map SHALL render the blind polyline titled "本次路线"
- **AND** the primary summary SHALL show blind distance, duration, and average pace
- **AND** visible text, VoiceOver, TTS, and repeat-status output SHALL provide equivalent information

#### Scenario: Track data is partial or empty
- **WHEN** the blind track or one or more statistics are absent
- **THEN** the app SHALL present an honest partial/unavailable state
- **AND** it SHALL NOT substitute demo points or fabricate statistics

### Requirement: Volunteer track is limited to approved anomaly comparison
The app SHALL decode the volunteer track and statistics but SHALL NOT present them as the default "本次路线" or claim an anomaly without an approved versioned comparison rule or backend result.

#### Scenario: Both tracks are returned
- **WHEN** the track endpoint returns blind and volunteer tracks
- **THEN** the blind track SHALL remain the user-facing primary route
- **AND** the volunteer track SHALL be supplied only to the approved anomaly-comparison component

#### Scenario: Anomaly policy is not approved
- **WHEN** no frozen backend assessment or product-approved threshold exists
- **THEN** the app SHALL NOT display an abnormality conclusion derived from volunteer-track differences
