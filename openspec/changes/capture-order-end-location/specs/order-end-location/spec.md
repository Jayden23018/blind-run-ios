## ADDED Requirements

### Requirement: An order MAY carry an optional end location
The app SHALL support an optional end location on a booking, consisting of a place name and, when available, its GCJ-02 coordinates. Absence of an end location SHALL mean "the user did not state one" and SHALL NOT be interpreted, displayed, or announced as "return to the start point".

#### Scenario: The utterance names an end location
- **WHEN** the parsing response for a booking utterance carries an end address
- **THEN** the app SHALL carry that end location forward into the create-order request
- **AND** it SHALL send the end latitude and end longitude together or not at all

#### Scenario: The utterance names no end location
- **WHEN** the parsing response carries no end address
- **THEN** the create-order request SHALL omit all three end-location fields
- **AND** no read-back, screen row, or announcement SHALL mention an end location at all

#### Scenario: A later utterance drops the end location
- **WHEN** the user restates the booking and the new utterance names no end location
- **THEN** the app SHALL clear the end location captured from the previous utterance
- **AND** the read-back SHALL NOT announce the previously captured end location

### Requirement: An end location without coordinates is kept, not discarded
The app SHALL keep an end location that has a place name but no coordinates, and SHALL state that the place could not be located. Discarding it silently is prohibited: the user stated the destination out loud, and a read-back that omits it leaves a blind user unable to tell whether the app failed to hear it or failed to store it.

#### Scenario: Geocoding could not resolve the spoken place
- **WHEN** the parsing response carries an end address with no end coordinates
- **THEN** the create-order request SHALL carry the end address with both coordinates omitted
- **AND** the read-back SHALL announce the place name together with a statement that it could not be located

#### Scenario: Only one of the two coordinates is present
- **WHEN** the parsing response carries an end address with exactly one of end latitude or end longitude
- **THEN** the app SHALL treat the end location as having no coordinates rather than sending a half coordinate

#### Scenario: Coordinates arrive without a place name
- **WHEN** the parsing response carries end coordinates but no end address
- **THEN** the app SHALL treat the response as carrying no end location

### Requirement: The end location is read back immediately after the start location
The app SHALL announce the end location directly after the start location and before any other booking field. Start and end are extracted by a language model and can be swapped; the read-back is the only place a blind user can detect the swap, and adjacent announcement is what makes the swap audible.

#### Scenario: Both places are announced in the confirmation read-back
- **WHEN** the app reads the booking back for confirmation and an end location is present
- **THEN** the end location SHALL be announced after the start location and before the appointment time

### Requirement: Both roles see the end location on the order detail
The app SHALL display the end location on the blind runner's and the volunteer's order detail. When the order carries no end location the row SHALL NOT be rendered. When the end location has no coordinates the display SHALL mark it as not located, because a volunteer cannot navigate to it and must ask in person instead.

#### Scenario: The order carries a located end location
- **WHEN** an order detail carrying an end address and end coordinates is displayed
- **THEN** both roles SHALL see an end-location row showing that address

#### Scenario: The order carries no end location
- **WHEN** an order detail carrying no end address is displayed
- **THEN** no end-location row SHALL be rendered for either role

#### Scenario: An order status update arrives over the realtime channel
- **WHEN** an order's status is updated from a realtime message
- **THEN** the retained order SHALL keep its end location unchanged

### Requirement: The parse wait tolerates the model-backed round trip
The app SHALL allow a single booking-utterance parse enough time to complete the server's model-backed extraction plus network round trip, and SHALL surface its own spoken timeout message rather than a transport error when that budget is exceeded.

#### Scenario: The server takes longer than its own fast path
- **WHEN** a booking-utterance parse has not returned within the client's parse budget
- **THEN** the app SHALL announce that it could not turn the utterance into a booking and SHALL read back the defaults
- **AND** the transport layer SHALL NOT time out before the client's own parse budget elapses
