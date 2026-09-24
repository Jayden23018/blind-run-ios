# post-run-record Specification

## Purpose
Defines how the iOS app reads post-run records and monthly run history from the backend, posts run messages, and contributes each phone's own motion and GPS-quality data to those records during an active run.
## Requirements
### Requirement: Post-run record responses decode without losing the record
The iOS app SHALL decode `GET /api/orders/{id}/run-record` through the `ApiResponse` envelope into a typed record whose response-side enums are open, and SHALL NOT fail the whole record because of an unrecognized enum value.

#### Scenario: Backend adds a new record status or viewer role
- **WHEN** `status`, `viewerRole`, or a message `fromRole` carries a value the app does not recognize
- **THEN** the record SHALL still decode
- **AND** that field SHALL resolve to an explicit unknown value rather than any recognized value

#### Scenario: Backend adds a new event type or message type
- **WHEN** `events[]` contains an unrecognized `type`, or `messages[]` contains an unrecognized `type`
- **THEN** that single event or message SHALL be skipped
- **AND** every other event, message, and field SHALL still be available

#### Scenario: A quantity has no data
- **WHEN** the backend sends `null` for a summary quantity, split cadence, comparison, track, stop coordinate, or service duration
- **THEN** the decoded value SHALL be absent, never `0`

#### Scenario: Record is still generating, failed, or has too few points
- **WHEN** `status` is `GENERATING`, `FAILED`, or `INSUFFICIENT_TRACK`
- **THEN** the record SHALL decode with its computed fields absent or empty
- **AND** names, service time, events, and messages that the backend still sends SHALL remain available

### Requirement: Monthly run history is read per role
The iOS app SHALL read `GET /api/orders/mine/run-records?month=YYYY-MM` for the signed-in role and decode the month summary and items with the same open-enum and null-is-absent rules as the single record.

#### Scenario: Month is requested
- **WHEN** the app requests a month's history
- **THEN** the request SHALL carry `month` formatted as `YYYY-MM`
- **AND** items SHALL keep the backend's order (finished time descending)

#### Scenario: Runner-side history
- **WHEN** the signed-in role is the blind runner
- **THEN** item thumbnails and the month's service minutes SHALL be absent as sent by the backend, not synthesized by the client

### Requirement: Run messages are posted as text only
The iOS app SHALL post run messages to `POST /api/orders/{id}/run-record/messages` with body `{"type":"TEXT","text":...}` and SHALL surface backend errors to the caller instead of swallowing them.

#### Scenario: Message is accepted
- **WHEN** the backend returns 201 with the created message
- **THEN** the caller SHALL receive that message decoded with the same rules as `messages[]` in the record

#### Scenario: Message is rejected
- **WHEN** the backend returns 400, 403, 404, or 409
- **THEN** the caller SHALL receive the typed API error

### Requirement: Location updates carry optional run-quality fields
During an owned `IN_PROGRESS` escort session, each phone's `LOCATION_UPDATE` SHALL add the optional fields `hAcc`, `speed`, `alt`, `steps`, and `cadence` when, and only when, the phone has a valid value for them.

#### Scenario: All values are available
- **WHEN** the location sample has a non-negative horizontal accuracy and speed, and motion data is available
- **THEN** the message SHALL carry `hAcc` in metres, `speed` in metres per second, `alt` as barometric relative altitude in metres, `steps` as the cumulative step count since this phone's run start, and `cadence` in steps per minute

#### Scenario: A value is unavailable
- **WHEN** Core Location reports a negative (invalid) accuracy or speed, motion permission is not granted, the device lacks the sensor, or no motion reading has arrived yet
- **THEN** that field SHALL be omitted from the message
- **AND** it SHALL NOT be sent as `0`

#### Scenario: Location is sent outside IN_PROGRESS
- **WHEN** a `LOCATION_UPDATE` is sent in `DRIVER_EN_ROUTE`, `DRIVER_ARRIVED`, idle volunteer availability, or dispatch acceptance
- **THEN** it SHALL NOT carry `alt`, `steps`, or `cadence`

### Requirement: Both phones collect their own motion data during the run
The blind runner's phone and the volunteer's phone SHALL each collect steps, cadence, and relative altitude for themselves while their owned order is `IN_PROGRESS`, and SHALL stop when the order leaves `IN_PROGRESS` or the session ends.

#### Scenario: Run starts
- **WHEN** the owned order first enters `IN_PROGRESS` on this phone
- **THEN** this phone SHALL record that moment as its run start for that order
- **AND** steps SHALL be counted cumulatively from that run start

#### Scenario: App relaunches during the same run
- **WHEN** the app is terminated and relaunched while the same order is still `IN_PROGRESS`
- **THEN** the step count SHALL continue from the same run start and SHALL NOT restart from zero
- **AND** reported relative altitude SHALL continue from the last reported value instead of jumping back to zero

#### Scenario: Run ends
- **WHEN** the order leaves `IN_PROGRESS` or the escort session is cleared
- **THEN** motion collection SHALL stop

### Requirement: Motion permission is requested before the run
Both roles SHALL request Motion & Fitness permission when their owned escort session starts (`DRIVER_EN_ROUTE`), so the system prompt does not appear at the start of running.

#### Scenario: Permission not yet decided at escort start
- **WHEN** an owned order becomes `DRIVER_EN_ROUTE` and Motion & Fitness permission has not been decided
- **THEN** the app SHALL trigger the system permission request once

#### Scenario: Permission denied
- **WHEN** Motion & Fitness permission is denied or restricted
- **THEN** location reporting SHALL continue unchanged without `steps`, `cadence`, or `alt`
- **AND** the app SHALL NOT block the run or repeatedly prompt

### Requirement: Tests and Mock never touch motion hardware
Unit-test hosts and the in-process Mock environment SHALL NOT start pedometer or altimeter updates or trigger the Motion & Fitness prompt.

#### Scenario: Unit tests drive an IN_PROGRESS session
- **WHEN** tests move an escort session into `IN_PROGRESS`
- **THEN** no CoreMotion updates SHALL start on the device

#### Scenario: UI tests run in Mock
- **WHEN** a UI test reaches `DRIVER_EN_ROUTE` or `IN_PROGRESS` in the Mock environment
- **THEN** no Motion & Fitness system prompt SHALL appear

### Requirement: Responsibilities are split with live escort location and track summary
This capability SHALL only extend the payload of the live escort `LOCATION_UPDATE` and add run-record data access; cadence, background continuity, GCJ-02 normalization, peer positions, separation alerts, and the `/track`-based completed summary remain owned by `live-escort-location-and-track-summary`.

#### Scenario: Location cadence and coordinates
- **WHEN** a location update is sent during an escort session
- **THEN** its timing, background behavior, coalescing, and GCJ-02 `lat`/`lng` SHALL be exactly those defined by `live-escort-location-and-track-summary`
- **AND** this capability SHALL only add the optional fields defined above

#### Scenario: Completed-run summary during this stage
- **WHEN** an order is completed before the run-record screens exist
- **THEN** the existing `/track`-based completed summary SHALL remain the user-facing summary
- **AND** replacing it with the run-record detail (DECISIONS D13) SHALL be a later change that modifies that requirement explicitly

