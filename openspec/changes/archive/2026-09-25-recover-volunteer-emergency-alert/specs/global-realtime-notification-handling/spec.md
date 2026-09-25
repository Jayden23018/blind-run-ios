## ADDED Requirements

### Requirement: Volunteer emergency alert survives app restarts
The app SHALL recover the escorting volunteer's emergency alert from `GET /api/emergency/active` whenever it recovers realtime state (WebSocket reconnect, return to foreground, cold-start session restore), and SHALL show the distance to the runner as a band from the device fix or, failing that, from the server-computed distance.

#### Scenario: Volunteer reopens the app during an open emergency
- **WHEN** a volunteer session recovers and the endpoint returns a non-terminal event that is not `COUNTDOWN`
- **THEN** the volunteer alert SHALL be restored for that event, full screen unless `volunteerConfirmedAt` is set
- **AND** its elapsed time SHALL count from `triggeredAt`, never from a time later than now
- **AND** the volunteer's own SOS state SHALL NOT change

#### Scenario: Event is still counting down
- **WHEN** the endpoint returns an event in `COUNTDOWN`
- **THEN** no volunteer alert SHALL be shown

#### Scenario: Emergency ended while the app was away
- **WHEN** the endpoint returns no open event
- **THEN** any local volunteer alert SHALL be cleared
- **AND** a failed request SHALL leave the current alert unchanged

#### Scenario: Device has no location fix yet
- **WHEN** the alert has no usable device distance and the push carried `distanceBand` `NEARBY`, `CLOSE` or `FAR` with `distanceMeters`
- **THEN** the distance line SHALL show the band for the server distance
- **AND** when the band is `UNKNOWN`, unrecognised or missing, no distance line SHALL be shown
