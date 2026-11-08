## MODIFIED Requirements

### Requirement: Associated participants receive fresh peer positions
The iOS app SHALL present fresh peer positions only to the blind runner and volunteer associated with the same eligible order. Both roles SHALL judge peer-sample freshness with one shared 15-second threshold, and the blind runner's REST fallback SHALL use the same threshold to decide whether the WebSocket sample is still fresh.

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

#### Scenario: A visible peer sample reaches its freshness deadline
- **WHEN** a matching peer sample is accepted or replaced
- **THEN** each order page SHALL have at most one cancellable 15-second expiry pending for its peer marker
- **AND** an obsolete expiry, wrong-order sample, or late sample SHALL NOT clear a newer marker
- **AND** page exit, order termination, or order replacement SHALL cancel the expiry and clear the marker
- **AND** the app SHALL NOT use a dynamic periodic SwiftUI timeline to poll peer freshness or refresh the full map tree

#### Scenario: Both roles apply the same freshness threshold
- **WHEN** a matching peer sample captured 14 seconds ago arrives on either role's order page
- **THEN** the marker SHALL update
- **AND** a matching sample captured 16 seconds ago SHALL NOT update the marker on either role's order page

#### Scenario: REST fallback uses the shared threshold
- **WHEN** the blind runner's WebSocket is connected and its latest volunteer sample was captured 16 seconds ago during `IN_PROGRESS`
- **THEN** the order page SHALL request `GET /api/blind/volunteer-location` on the next poll
- **AND** when the latest sample was captured 14 seconds ago it SHALL NOT request it
