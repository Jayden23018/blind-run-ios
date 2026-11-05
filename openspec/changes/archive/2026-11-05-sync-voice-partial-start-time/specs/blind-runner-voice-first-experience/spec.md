## ADDED Requirements

### Requirement: A half-spoken start time is echoed back so a one-word answer completes it
When the voice parse reports that only part of the start time was heard (a date or a period without a clock time), the iOS blind-runner booking flow SHALL send that partial value back, unchanged, with the next round's request, so that the user can answer with the clock time alone. The server keeps no conversation state, so without this the answer is resolved against today instead of the date the user already said.

#### Scenario: The partial start time rides along with the next round
- **WHEN** a parse response carries a partial start time (a date, a period, or both) and the user answers in the following round
- **THEN** the next parse request SHALL carry that partial start time inside the previous-round slot snapshot
- **AND** the value SHALL be taken from the response, never constructed by the client
- **AND** this SHALL hold even when the start place falls back to the device location, because a half-spoken time usually comes without a start place

#### Scenario: An unknown period value is preserved
- **WHEN** the partial start time carries a period value the app does not recognise
- **THEN** the app SHALL NOT fail to decode the response
- **AND** it SHALL send the period back exactly as received

#### Scenario: Nothing is sent when there is nothing to send
- **WHEN** a response has no partial start time, or both of its fields are empty
- **THEN** the next request SHALL NOT include a partial start time

#### Scenario: A partial start time is not a confirmed start time
- **WHEN** only a partial start time is known
- **THEN** the previous-round snapshot SHALL leave the planned start time empty
- **AND** the booking SHALL NOT be treated as having a start time captured
