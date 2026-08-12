## MODIFIED Requirements

### Requirement: Booking uses a guided voice-first sequence
The iOS blind-runner booking flow SHALL accept the whole booking in a single spoken utterance, read the resulting order back, and let the user confirm it, change any single item of it, ask to hear it again, or abandon it — without repeating the whole utterance. Per-field guided steps SHALL remain reachable as the fallback path.

#### Scenario: Speak the booking in one utterance
- **WHEN** voice booking starts and every non-slot booking gate is satisfied
- **THEN** the app SHALL begin recording immediately and prompt for one utterance covering where, when, and how long
- **AND** the whole transcript SHALL be submitted in a single request to the full-utterance parsing endpoint, which extracts all three slots at once
- **AND** this first request SHALL NOT carry a previous-round slot snapshot, because there is no previous round
- **AND** whatever the parser cannot extract SHALL retain its prepared default rather than blocking progress
- **AND** this step SHALL NOT re-ask and SHALL NOT abandon the flow on a parse or transport failure

#### Scenario: Start place is extracted from the full utterance
- **WHEN** the app parses a full booking utterance
- **THEN** it SHALL take the start place from that same parse, because the full-utterance endpoint extracts a place-name span before geocoding it rather than forwarding the raw transcript to forward geocoding
- **AND** it SHALL NOT submit a full sentence to the address-resolution endpoint, which is reserved for a bare place name spoken during a targeted place correction
- **AND** when the parse reports no start place, the start place SHALL default to the current resolved location
- **AND** because the parse cannot distinguish "the user named no place" from "the user named a place that failed to resolve", the read-back SHALL state the start place actually being used

#### Scenario: Read the order back before creating it
- **WHEN** parsing of a full utterance completes
- **THEN** the app SHALL speak, in one uninterrupted passage, the recognized utterance, the resulting start place, appointment time, and optional needs, and the available next actions
- **AND** the available next actions SHALL include changing a single item, stated with an example, because a user who cannot see the screen has no other way to discover that a single item can be changed
- **AND** any value the app adjusted on the user's behalf SHALL be stated in that same passage rather than in a separate earlier announcement
- **AND** the app SHALL NOT create the order until the user's response is classified as a confirmation

#### Scenario: Confirm creates the order
- **WHEN** the spoken response after read-back is classified as a confirmation, either by the conservative local allowlist or by the backend intent field
- **THEN** the app SHALL create the order through the existing `POST /api/orders` request shape
- **AND** a response matching the local allowlist SHALL be classified locally without any network round trip, so that confirming remains instant and survives a failed or slow network
- **AND** the local allowlist SHALL remain a subset of the backend's deterministic intent patterns, so the two layers cannot reach different conclusions about the same sentence
- **AND** the app SHALL NOT speak the backend's confirmation copy, because that copy is worded as though the order already exists while the parsing endpoint has no side effects

#### Scenario: Change one item without repeating the utterance
- **WHEN** the spoken response after read-back names a new value for part of the order
- **THEN** the app SHALL submit that response together with the previous round's slot snapshot, so the backend can overwrite what was newly spoken and inherit what was not
- **AND** every slot the user did not mention SHALL survive unchanged, including the end place and the optional needs
- **AND** the app SHALL read the whole order back again afterwards, because a correction the user cannot verify is worse than no correction
- **AND** the app SHALL NOT return to the single-utterance step and SHALL NOT clear any slot

#### Scenario: Name an item to change without giving a value
- **WHEN** the backend reports that the user named which item to change but gave no new value
- **THEN** the app SHALL speak the backend's targeted follow-up prompt for that item and record one more response
- **AND** the slot snapshot SHALL be sent again unchanged with that response, so the new value overwrites only the named item
- **AND** this exchange SHALL NOT count toward the misrecognition limit, because the request was understood and the flow is progressing
- **AND** the app SHALL NOT change to a different step or replace the screen with a different form

#### Scenario: Reject the read-back without saying what is wrong
- **WHEN** the backend reports that the user rejected the read-back but did not identify an item
- **THEN** the app SHALL speak the backend's disambiguation question and record one more response
- **AND** this exchange SHALL count toward the misrecognition limit, because nothing was understood
- **AND** the slot snapshot SHALL NOT be cleared, because forcing the whole utterance again is the outcome this flow exists to avoid

#### Scenario: Hear the order again
- **WHEN** the response after read-back asks for the order to be repeated
- **THEN** the app SHALL speak the previous read-back passage again
- **AND** no slot SHALL change and the snapshot SHALL NOT be cleared
- **AND** a request to hear it again SHALL NEVER be treated as a request to restart, because the costs are asymmetric: restarting discards the utterance the user just finished

#### Scenario: Restart the whole utterance
- **WHEN** the user asks to say it again
- **THEN** the app SHALL return to the single-utterance step and clear every slot the previous utterance filled, because a slot left over from the previous round would be read back as if the user had just said it
- **AND** the slot snapshot SHALL be cleared as well, so the next utterance is not merged with the discarded round
- **AND** a restart SHALL NOT create the order

#### Scenario: Abandon the booking by voice
- **WHEN** the response after read-back is classified as abandoning the booking
- **THEN** the app SHALL end the voice flow and SHALL NOT record another response
- **AND** it SHALL speak where the user is now and that the form remains available, because someone who cannot see the screen has no other way to know voice stopped
- **AND** it SHALL NOT create the order

#### Scenario: The response cannot be classified at all
- **WHEN** the response after read-back matches no local phrase and the classification request fails
- **THEN** the app SHALL re-ask in place and restate the actions that still work without a network, which are confirming and restarting
- **AND** the spoken reason SHALL NOT claim the app misheard the user, because recognition succeeded and rewording will not help
- **AND** it SHALL NOT create the order and SHALL NOT advance
- **AND** repeated failures SHALL fall back to the form with a spoken reason

#### Scenario: Confirm start point
- **WHEN** the blind runner manually edits the start point
- **THEN** the step SHALL present the current resolved start point as text and speech-ready summary
- **AND** the user SHALL be able to keep the default current location or search for a different AMap POI
- **AND** speech input for start-place search SHALL remain field-level and SHALL auto-search after recognition completes with non-empty text

#### Scenario: Confirm appointment time
- **WHEN** the blind runner manually edits the appointment time
- **THEN** the app SHALL use the iOS system `DatePicker`
- **AND** the selected appointment time SHALL be constrained to at least 30 minutes in the future
- **AND** invalid appointment time state SHALL be shown visually and spoken through error or repeat-status copy before submission is allowed

#### Scenario: Add optional running needs
- **WHEN** the blind runner reaches optional running-needs input
- **THEN** route notes, expected duration, pace preference, route preference, guide-dog flag, and special notes SHALL remain optional
- **AND** optional text fields MAY use field-level speech input
- **AND** empty optional fields SHALL be omitted from the spoken review summary

#### Scenario: Review and submit booking
- **WHEN** all required booking gates are satisfied
- **THEN** the review step SHALL summarize start point, appointment time, and any filled optional needs before submission
- **AND** the submit action SHALL call the existing `POST /api/orders` request shape
- **AND** submission success SHALL navigate to the order status flow and speak that the order was submitted

## ADDED Requirements

### Requirement: A slot snapshot never carries a value the user did not speak
The app SHALL build the slot snapshot it sends back to the backend only from the previous parse response, never from the booking view model.

#### Scenario: Appointment time was never spoken
- **WHEN** the app sends a response for classification after a read-back in which no appointment time was extracted
- **THEN** the snapshot SHALL carry no appointment time
- **AND** the app SHALL NOT substitute the booking view model's prepared appointment time, because that value is a prepared default the user never spoke and the backend would inherit it, read it back, and create an order around it

#### Scenario: A place resolved to a name but not to coordinates
- **WHEN** a parse returns a place name that could not be geocoded
- **THEN** the snapshot SHALL carry that name with no coordinates, because the backend accepts this shape and rejecting it would strand the user in a loop only the backend can exit
- **AND** the snapshot SHALL NEVER carry coordinates without the corresponding name
