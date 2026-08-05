## MODIFIED Requirements

### Requirement: Booking uses a guided voice-first sequence
The iOS blind-runner booking flow SHALL accept the whole booking in a single spoken utterance, read the resulting order back, and require an explicit spoken confirmation before creating it. Per-field guided steps SHALL remain reachable as targeted corrections and as the fallback path.

#### Scenario: Speak the booking in one utterance
- **WHEN** voice booking starts and every non-slot booking gate is satisfied
- **THEN** the app SHALL begin recording immediately and prompt for one utterance covering where, when, and how long
- **AND** the whole transcript SHALL be submitted in a single request to the full-utterance parsing endpoint, which extracts all three slots at once
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
- **THEN** the app SHALL speak, in one uninterrupted passage, the recognized utterance, the resulting start place, appointment time, and optional needs, and both available next actions
- **AND** any value the app adjusted on the user's behalf SHALL be stated in that same passage rather than in a separate earlier announcement
- **AND** the app SHALL NOT create the order until the user speaks an affirmative

#### Scenario: Confirm creates the order
- **WHEN** the user speaks an affirmative from a conservative local allowlist
- **THEN** the app SHALL create the order through the existing `POST /api/orders` request shape
- **AND** the app SHALL NOT call a backend parsing endpoint to classify this confirmation

#### Scenario: Targeted correction
- **WHEN** the user names a single field to change
- **THEN** the app SHALL move to that field's guided step and request only that value
- **AND** a successful correction SHALL return to the read-back so the whole order is heard again
- **AND** a correction SHALL NOT create the order

#### Scenario: Command is not understood
- **WHEN** the spoken response after read-back matches neither an affirmative nor a named field
- **THEN** the app SHALL re-ask in place, restating both available next actions
- **AND** it SHALL NOT create the order and SHALL NOT advance
- **AND** repeated failures SHALL fall back to the form with a spoken reason

#### Scenario: Confirm start point
- **WHEN** the blind runner corrects or manually edits the start point
- **THEN** the step SHALL present the current resolved start point as text and speech-ready summary
- **AND** the user SHALL be able to keep the default current location or search for a different AMap POI
- **AND** speech input for start-place search SHALL remain field-level and SHALL auto-search after recognition completes with non-empty text

#### Scenario: Confirm appointment time
- **WHEN** the blind runner corrects or manually edits the appointment time
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

### Requirement: Booking has exactly one entry point
The blind-runner home SHALL expose a single booking action. Presenting a form entry and a voice entry side by side forces a choice before every booking between two paths that open the same screen.

#### Scenario: Home exposes one booking action
- **WHEN** a logged-in blind-runner user without an active order opens the home screen
- **THEN** exactly one booking action SHALL be present
- **AND** activating it SHALL open booking with voice already running
- **AND** the form SHALL remain reachable from within booking without leaving the screen

### Requirement: Recording state is perceivable without sight
Every start and end of recording SHALL be signalled through both an audible cue and a haptic cue, independent of any on-screen indicator. A blind user has no way to discover from the screen whether the microphone is open, and silence is indistinguishable from a failed start.

#### Scenario: Recording starts
- **WHEN** speech recognition begins capturing audio
- **THEN** the app SHALL emit an audible start cue and a haptic start cue

#### Scenario: Recording ends
- **WHEN** a capturing recognition session ends for any reason
- **THEN** the app SHALL emit an audible end cue and a haptic end cue
- **AND** the audible cue SHALL be emitted after the audio session is restored to playback, so it is not routed into the recording path

#### Scenario: Recognized text during recording
- **WHEN** partial recognition results arrive while recording
- **THEN** they SHALL be shown on screen
- **AND** they SHALL NOT be spoken, because speaking over the user corrupts both the recognition and the user's own train of thought

#### Scenario: Ending an utterance
- **WHEN** the user has finished speaking
- **THEN** the whole content area SHALL act as the end-of-utterance control, labelled for screen-reader use
- **AND** an automatic end on sustained silence SHALL remain available as a secondary path
- **AND** the silence threshold for a whole-booking utterance SHALL be substantially longer than for single-field dictation

#### Scenario: Motion sensitivity
- **WHEN** a recording indicator is animated
- **THEN** it SHALL flash no more than three times per second
- **AND** it SHALL degrade to a static indicator when the system reduce-motion preference is enabled
- **AND** no state SHALL be conveyed by animation alone

### Requirement: Voice booking always reaches an audible terminal outcome
Every voice-booking attempt SHALL end in a state the user can hear. A blind user has no way to observe that the speech path has silently stopped, so the app SHALL NOT leave the wizard in a running state without a pending prompt, an in-flight request, or an announced fallback.

#### Scenario: Speech recognition cannot start
- **WHEN** speech authorization, microphone authorization, recognizer availability, audio-session configuration, or microphone input makes recognition impossible to start
- **THEN** the speech input service SHALL deliver exactly one terminal completion carrying an error stop reason to the caller that requested recognition
- **AND** the wizard SHALL leave its running state, announce that voice booking stopped and that the on-screen form remains available, and expose that reason as visible text

#### Scenario: Voice path is known to be unavailable before starting
- **WHEN** voice booking is requested and the speech path is already known to be unusable
- **THEN** the app SHALL NOT begin the re-ask cycle
- **AND** it SHALL announce the reason once and present the form immediately

#### Scenario: Repeated startup failures do not repeat announcements
- **WHEN** a terminal completion has already been delivered for a recognition session
- **THEN** no further completion, cleanup, or announcement SHALL be produced for that session

#### Scenario: Interface failure during a targeted correction
- **WHEN** a correction step's parse request fails at the API layer rather than timing out
- **THEN** the app SHALL fall back to the form with the reason spoken, rather than re-asking
- **AND** a timeout SHALL instead re-ask and count toward the re-ask limit
