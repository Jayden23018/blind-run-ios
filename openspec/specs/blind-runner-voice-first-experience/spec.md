# blind-runner-voice-first-experience Specification

## Purpose
Define a voice-first, accessible blind-runner experience in which current state and primary actions precede auxiliary map content, booking follows a guided sequence, and speech feedback remains concise and reliable.
## Requirements
### Requirement: Blind-runner home is voice-first
The iOS blind-runner home SHALL present the current service state or next primary action before auxiliary visual map content **in VoiceOver traversal order**. Visual order is not constrained, provided the auxiliary map remains non-interactive and carries no information that is unavailable in text elsewhere on the screen.

#### Scenario: No active order
- **WHEN** a logged-in blind-runner user opens the home screen without an active order
- **THEN** the first meaningful content SHALL summarize that there is no active booking and expose the "开始约跑" primary action
- **AND** the "开始约跑" action SHALL have a minimum 64pt touch target and clear `accessibilityLabel` and `accessibilityHint`
- **AND** current-location text and auxiliary map content SHALL NOT precede the primary action in VoiceOver traversal

#### Scenario: Active order exists
- **WHEN** a logged-in blind-runner user opens the home screen with an active order
- **THEN** the first meaningful content SHALL summarize the current order status, appointment time, and start address when available
- **AND** the screen SHALL expose "查看当前订单" before auxiliary map content in VoiceOver traversal
- **AND** cancellation SHALL be visible only when the active order status allows blind-runner cancellation

#### Scenario: Repeat status on home
- **WHEN** the user activates "重复当前状态" on the blind-runner home
- **THEN** the app SHALL speak a concise summary of the current no-order or active-order state
- **AND** the spoken summary SHALL include the selected or current start location when that information is meaningful
- **AND** the app SHALL post the same important summary as a VoiceOver announcement

### Requirement: Blind-runner maps are auxiliary
The iOS blind-runner experience SHALL keep AMap-backed location confirmation available while treating visual map inspection as secondary to spoken and textual state.

#### Scenario: Map content is not the primary task surface
- **WHEN** a blind-runner screen includes a map for current location or order start location
- **THEN** the map SHALL NOT precede the current state, next action, or repeat-status controls in VoiceOver traversal
- **AND** where the map is purely decorative and non-interactive, it SHALL be hidden from assistive technologies outright rather than merely reordered — SwiftUI binds VoiceOver traversal to paint order, so a map painted behind foreground content cannot be sorted after it (`accessibilitySortPriority` is a no-op across overlapping layers; see `docs/research/swiftui-voiceover-traversal-order-20260814.md`)
- **AND** where the map does carry information, it SHALL have an accessibility label that identifies it as auxiliary visual confirmation
- **AND** the screen SHALL provide equivalent textual/TTS location information outside the map

#### Scenario: Raw coordinates remain hidden
- **WHEN** the blind-runner home, booking, or order status screen displays location information
- **THEN** raw latitude and longitude SHALL NOT be shown as normal user-facing text
- **AND** coordinates SHALL remain available in models, API requests, distance calculations, and map annotations

#### Scenario: Location fallback is explicit
- **WHEN** the app uses a demo fallback coordinate or cannot resolve a real address
- **THEN** the blind-runner UI and repeat-status speech SHALL clearly identify the fallback or unresolved state
- **AND** the app SHALL NOT imply that a demo fallback coordinate is the user's real meeting point

### Requirement: Booking uses a guided voice-first sequence
The iOS blind-runner booking flow SHALL accept the whole booking in a single spoken utterance, resolve an ambiguous start place by letting the user choose among the places the backend found, read the resulting order back, and let the user confirm it, change any single item of it, ask to hear it again, or abandon it — without repeating the whole utterance. Per-field guided steps SHALL remain reachable as the fallback path.

#### Scenario: Speak the booking in one utterance
- **WHEN** voice booking starts and every non-slot booking gate is satisfied
- **THEN** the app SHALL begin recording immediately and prompt for one utterance covering where, when, and how long
- **AND** the whole transcript SHALL be submitted in a single request to the full-utterance parsing endpoint, which extracts all three slots at once
- **AND** this first request SHALL NOT carry a previous-round slot snapshot, because there is no previous round
- **AND** whatever the parser cannot extract SHALL retain its prepared default rather than blocking progress
- **AND** this step SHALL NOT re-ask and SHALL NOT abandon the flow on a parse or transport failure

#### Scenario: The parse request carries the user's current coordinates
- **WHEN** voice booking starts
- **THEN** the app SHALL request one fresh location fix at that moment, rather than relying on the continuous location stream
- **AND** the coordinates attached to the parse request SHALL be accepted even when the last fix is several minutes old
- **AND** the app SHALL NOT apply the short freshness window used by features that need a live position, because the user stands still while speaking a whole utterance and the continuous stream emits nothing while stationary
- **AND** when no real device coordinate is available the request SHALL simply omit both coordinates rather than substitute a placeholder
- **AND** this matters beyond ranking: without coordinates the backend cannot offer candidates at all and resolves the place name against the whole country

#### Scenario: Start place is extracted from the full utterance
- **WHEN** the app parses a full booking utterance
- **THEN** it SHALL take the start place from that same parse, because the full-utterance endpoint extracts a place-name span before geocoding it rather than forwarding the raw transcript to forward geocoding
- **AND** it SHALL NOT submit a full sentence to the address-resolution endpoint, which is reserved for a bare place name spoken during a targeted place correction
- **AND** when the parse reports no start place, the start place SHALL default to the current resolved location

#### Scenario: A named start place could not be resolved
- **WHEN** the parse reports that a place name was heard but could not be turned into a usable start place
- **THEN** the app SHALL say so before the read-back, and SHALL say which start place is being used instead
- **AND** it SHALL NOT silently fall back to the current location, because the user did name a place and would be sent to a start point he never chose
- **AND** this SHALL be distinguished from "no place was named", where falling back to the current location is correct and needs no announcement

#### Scenario: Choose between same-name start places
- **WHEN** the parse returns two or more candidate places for the start place
- **THEN** the app SHALL speak the backend's candidate announcement and record one more response, before reading the order back
- **AND** the announcement SHALL come from the backend, because only it knows each candidate's name, district, and distance
- **AND** this step SHALL come before the read-back, because the read-back states the best guess and a user who then confirms would have created an order around a place he was never offered the chance to reject
- **AND** the ordinal spoken in reply SHALL be matched locally, without any network round trip
- **AND** the reply to this step SHALL NOT be sent to the parsing endpoint, because an ordinal is not a place name and would be extracted as one, overwriting the place just chosen
- **AND** the chosen candidate SHALL replace the start place in the slot snapshot as well, so the next round does not inherit the best guess
- **AND** the candidate list SHALL NOT be offered again for a start place inherited from a previous round
- **AND** candidates SHALL NEVER be offered for the end place, because announcing both lists exceeds what a listener can hold

#### Scenario: The choice between candidates cannot be recognized
- **WHEN** the response in the candidate step matches no ordinal
- **THEN** the app SHALL re-ask, restating the ordinals and the way out
- **AND** each such response SHALL count toward the misrecognition limit
- **AND** on reaching the limit the app SHALL adopt the first candidate and SHALL say that it did so, rather than returning to the form, because a usable best guess is already in hand and the read-back still lets the user reject it
- **AND** adopting the first candidate silently SHALL NOT be an accepted outcome
- **AND** a request to start over SHALL be honoured at any point in this step

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
- **AND** repeated failures SHALL end the voice session on the voice stage with a spoken reason (see `end-voice-failures-on-voice-stage`)

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

### Requirement: Voice feedback is concise and repeatable
The iOS blind-runner flow SHALL provide coherent TTS and VoiceOver feedback for guided booking without creating speech spam.

#### Scenario: Step summary changes
- **WHEN** the user moves between guided booking steps
- **THEN** the app SHALL make the new step's purpose and current value available through visible text and repeat-status speech
- **AND** the app SHALL NOT automatically speak long summaries after every keystroke or picker adjustment

#### Scenario: Repeat status during booking
- **WHEN** the user activates "重复当前状态" during booking
- **THEN** the app SHALL speak the current step, current selected value, and the next expected action
- **AND** error or blocked state SHALL be included when submission cannot proceed

#### Scenario: Search result feedback
- **WHEN** a start-place search returns results
- **THEN** the app SHALL announce the result count and first result name
- **AND** each selectable result SHALL expose place name and address in its accessibility label
- **AND** the app SHALL NOT announce raw coordinates as part of normal result feedback

#### Scenario: Speech input restores audible feedback
- **WHEN** field-level speech input ends manually, with a final result, after silence or maximum duration, because of an error, or because the field leaves the screen
- **THEN** the app SHALL stop recording and restore a playback-capable audio session before any completion, search-result, stop, or error TTS
- **AND** playback SHALL follow the current system output route without forcing the built-in speaker
- **AND** repeated stop callbacks SHALL NOT repeat cleanup or announcements

#### Scenario: Playback restoration fails
- **WHEN** iOS rejects an audio-session deactivation, category, or activation operation after speech input
- **THEN** recognized text, POI search completion, and keyboard fallback SHALL remain available
- **AND** the app SHALL preserve visible and VoiceOver feedback and record diagnostic information

### Requirement: Blind-runner presentation is high-contrast and low-density
The iOS blind-runner screens affected by this change SHALL use a high-contrast, low-density presentation suitable for repeated VoiceOver and touch use.

#### Scenario: Primary actions are large and stable
- **WHEN** a blind-runner primary action is rendered on home, booking, or order status screens
- **THEN** the action SHALL use at least a 64pt height
- **AND** loading, disabled, and destructive states SHALL remain visually and semantically distinct

#### Scenario: One primary task per screen region
- **WHEN** a blind-runner guided booking step is displayed
- **THEN** the screen SHALL emphasize one primary task for that step
- **AND** optional fields SHALL NOT obscure the required next action
- **AND** dense table-like layouts SHALL NOT be used for required blind-runner task completion

### Requirement: Location announcement falls back to the server and states its age
The app SHALL answer "播报我的位置" from the device fix first and, when that yields no place, from `GET /api/orders/{id}/location/address`, stating how old the server position is when it is older than 15 seconds. The volunteer's emergency alert SHALL use the same endpoint for the runner's place when it has no coordinate or local reverse geocoding fails. When the system "Precise Location" setting is off for the app, the app SHALL NOT announce any place derived from a coordinate, because both the device fix and the server copy are only an area representative point up to several kilometres away.

#### Scenario: Device has no usable place
- **WHEN** the runner asks for their location, precise location is on, and the device fix or its reverse geocode yields nothing
- **THEN** the app SHALL request the endpoint and read the address, else the coordinates, else the "暂时定位不到" sentence
- **AND** when `ageSeconds` is greater than 15 it SHALL append "这是N秒前的位置。"
- **AND** when `ageSeconds` is null it SHALL NOT mention an age

#### Scenario: Server request fails
- **WHEN** the endpoint request fails
- **THEN** the app SHALL read the "暂时定位不到" sentence rather than stay silent

#### Scenario: Precise location is off
- **WHEN** the runner asks for their location while precise location is off
- **THEN** the app SHALL NOT reverse geocode the device fix and SHALL NOT request the endpoint
- **AND** it SHALL read "「精确位置」已关闭，只能拿到大致位置，可能偏差几公里，所以念不出你的准确位置。请直接拨打120或110，说明你周围的情况；跑完后可在系统设置里为助盲跑打开「精确位置」。"
- **AND** it SHALL NOT trigger a system location prompt

#### Scenario: Precise location is on
- **WHEN** the runner asks for their location while precise location is on and the device has a real fix
- **THEN** the app SHALL reverse geocode the fix and read "你现在在<地名>附近。"

#### Scenario: Volunteer alert without a coordinate
- **WHEN** the volunteer alert has no coordinate or local reverse geocoding fails
- **THEN** the place line SHALL show the server address or coordinates with the age notice, or "暂时收不到他的位置" when there is neither

### Requirement: Volunteer is spoken by surname
Every spoken or VoiceOver reference to the volunteer on the runner side SHALL use `volunteerSurname` when present, and SHALL otherwise keep the existing masked-name-without-asterisk fallback. The visible masked name SHALL NOT change.

#### Scenario: Surname present
- **WHEN** the order has `volunteerName = "张*"` and `volunteerSurname = "欧阳"`
- **THEN** the spoken name SHALL be "欧阳"

#### Scenario: Surname absent
- **WHEN** the order has `volunteerName = "张*"` and no `volunteerSurname`
- **THEN** the spoken name SHALL be "张"

### Requirement: Voice booking failures end on the voice stage, not the form
When voice booking gives up because the user was repeatedly not understood, or because the user cancelled, the app SHALL end the voice session while keeping the voice stage on screen. The form SHALL NOT be presented as the fallback for these outcomes, because a blind user cannot practically complete it. The form SHALL remain reachable by an explicit control.

#### Scenario: Repeatedly not understood
- **WHEN** the same slot is re-asked up to the re-ask limit, or consecutive rounds end without a start time, and the parse endpoint is available
- **THEN** the app SHALL stop listening and speak "暂时没听清，你可以稍后再试，或者让身边的人帮忙。"
- **AND** the screen SHALL keep the voice stage, titled as ended, and SHALL NOT switch to the form
- **AND** tapping the voice stage SHALL start a new voice session
- **AND** when no booking gate is missing, the zero-input booking offer SHALL be shown on the voice stage

#### Scenario: User cancels by voice
- **WHEN** the user says a local cancel phrase or the backend classifies the utterance as CANCEL
- **THEN** the app SHALL speak "已取消这次语音下单。" without mentioning the form
- **AND** the screen SHALL keep the ended voice stage, without the zero-input booking offer

#### Scenario: Voice cannot work at all
- **WHEN** speech recognition is unavailable or the parse endpoint does not exist
- **THEN** the app SHALL keep falling back to the form with the reason spoken, because retrying cannot succeed

### Requirement: Re-trigger merged into the open emergency is announced as such
When the runner triggers SOS again and the backend merges it into the runner's open emergency (same `eventId`), the app SHALL say that no new request was created, SHALL NOT start a countdown, and SHALL present the sent-request screen again.

#### Scenario: Same eventId comes back
- **WHEN** the trigger response carries the `eventId` of the local active emergency and a status other than `COUNTDOWN`
- **THEN** screen and VoiceOver SHALL say "这次没有新建求助：你上一次的求助还在处理中，已更新你的位置，系统正在再次提醒客服跟进。若情况危急请立即拨打120或110。"
- **AND** the app SHALL NOT claim that a new request was sent or that contacts received a message
- **AND** the sent-request screen (screen 3b) SHALL be presented again

#### Scenario: Stale countdown deadline on a merged response
- **WHEN** the merged response has a dispatched status and a past, non-null `countdownEndsAt`
- **THEN** the app SHALL NOT count down and SHALL NOT offer the countdown cancel

#### Scenario: A different eventId comes back
- **WHEN** the trigger response carries a new `eventId`
- **THEN** the app SHALL use the status copy for a new request and SHALL NOT count it as a merge

### Requirement: Sent-request screen has one primary action
After an SOS is sent, the blind runner's full-screen status page SHALL offer exactly one primary action (call 120), SHALL group 110 and the primary contact behind one secondary action, and SHALL show when the request was sent.

#### Scenario: Request sent
- **WHEN** the screen shows a sent request
- **THEN** the only filled button SHALL be 「拨打120」 with 「急救电话」
- **AND** one outline button 「打 110 或紧急联系人」 SHALL open the shared call-options dialog with the message 「求助已经发出。你也可以自己打电话，请选择要拨打的号码。」
- **AND** cancelling SHALL be a quiet text button 「误触了？撤销求助」 with a 64 pt hit area that still asks for confirmation
- **AND** the header SHALL show the send time and how long ago, as 「刚刚」, 「N 分钟前」 or 「N 小时 M 分钟前」

#### Scenario: Re-trigger merged into the same request
- **WHEN** the request on screen has absorbed a later press
- **THEN** a timeline SHALL show 「发出求助」 and 「又按了一次，并入这一条」 with their times
- **AND** the timeline SHALL be hidden from VoiceOver

#### Scenario: Request not sent
- **WHEN** the request failed to send and no event exists
- **THEN** the actions SHALL be, in order, 「拨打120」, 「再发一次求助」, 「打 110 或紧急联系人」, and there SHALL be no cancel action

### Requirement: Booking has exactly one entry point
The blind-runner home SHALL expose a single booking action. Presenting a form entry and a voice entry side by side forces a choice before every booking between two paths that open the same screen.

#### Scenario: Home exposes one booking action
- **WHEN** a logged-in blind-runner user without an active order opens the home screen
- **THEN** exactly one booking action SHALL be present
- **AND** activating it SHALL open booking with voice already running
- **AND** the form SHALL remain reachable from within booking without leaving the screen

### Requirement: The voice stage and the form stage are mutually exclusive
While voice booking is running, the booking screen SHALL present the voice interaction only. A screen that shows the guided form alongside the voice prompt is a form with a microphone attached to each field, not a voice-first screen: the blind runner who chose to speak is handed a dozen static labels and two text fields to traverse before reaching anything actionable.

#### Scenario: Voice is running
- **WHEN** the voice wizard is running on the booking screen
- **THEN** the screen SHALL present a single status region occupying the content area, plus the read-back summary once the order has been read back
- **AND** it SHALL NOT render the guided step form, its text fields, its place search, or the auxiliary map
- **AND** the status region SHALL be one accessibility element whose label states the currently available action and whose value carries the text most recently spoken

#### Scenario: Ending the utterance while parsing
- **WHEN** a parse request is in flight
- **THEN** the status region SHALL remain present and state that recognition is in progress
- **AND** it SHALL NOT expose an activation action, because ending speech is a no-op while parsing and announcing an action that does nothing is worse than announcing none

#### Scenario: Leaving the voice stage
- **WHEN** the user stops voice booking, or the wizard falls back
- **THEN** the screen SHALL present the guided form
- **AND** the form SHALL resume at the step the wizard last read out, so what the user just heard is what the screen now shows
- **AND** re-entering voice SHALL remain available from the form without leaving the screen

### Requirement: A failed voice path offers a booking that needs no input
When voice booking gives up and every non-slot booking gate is already satisfied, the app SHALL offer to create the booking from the current location and the earliest bookable time without further input. Handing a blind runner whose microphone just failed a four-step form is the most expensive possible recovery, and the values that form would collect are already available.

#### Scenario: Offer appears only after voice gave up
- **WHEN** the wizard has announced a fallback and no booking gate is missing
- **THEN** the screen SHALL present a zero-input booking action above the form
- **AND** the offer SHALL NOT appear when the user stopped voice deliberately, nor when any booking gate is still missing

#### Scenario: Zero-input booking is reviewed before it is created
- **WHEN** the user activates the zero-input booking action
- **THEN** the app SHALL speak the resulting order and require a second activation before creating it
- **AND** the second action's accessibility label SHALL be that same order, stating the appointment time as an absolute moment rather than as "the earliest bookable time"
- **AND** a way to abandon the offer and return to the form SHALL be present alongside it

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

### Requirement: Every spoken prompt the system teaches must be one the app accepts
The wording the app speaks to elicit a spoken answer SHALL be kept in agreement with the matching the app performs on that answer, including when the wording originates in the backend.

#### Scenario: Ordinals announced by the backend
- **WHEN** the backend announces candidates using ordinal words
- **THEN** every ordinal word it can announce SHALL be recognized by the local matcher
- **AND** this SHALL be enforced mechanically rather than by review, because a user reading back exactly what the system just said and getting no response has no way to discover why
- **AND** the local matcher MAY accept additional spellings the backend never speaks
- **AND** an ordinal beyond the number of candidates announced SHALL NOT be accepted

### Requirement: SOS countdown is timed by the server
The runner's long-press SOS SHALL register a server-side countdown (`useCountdown`) and follow the returned `countdownEndsAt`. Cancelling SHALL withdraw it on the server, and the spoken result SHALL distinguish a request that was never sent from one that was sent and then cancelled.

#### Scenario: Countdown accepted by the server
- **WHEN** the trigger response is `COUNTDOWN` with `countdownEndsAt`
- **THEN** the app SHALL count down to that instant, announcing every second that cancelling is still possible
- **AND** at the deadline it SHALL say only that the request is recorded and being processed

#### Scenario: Server did not take the countdown
- **WHEN** the trigger response has no `countdownEndsAt`
- **THEN** the app SHALL treat the request as already sent and SHALL NOT count down

#### Scenario: Cancel during the countdown
- **WHEN** the runner cancels and the server answers `CANCELLED`
- **THEN** the app SHALL say "已撤回。求助没有发出，没有通知任何人。" without mentioning contacts or SMS
- **AND** when the server answers `FALSE_ALARM` it SHALL use the owner-cancel copy
- **AND** when the request fails it SHALL say the request may already have been sent and keep the event

#### Scenario: Countdown recovered after reconnect
- **WHEN** `GET /api/emergency/active` returns the runner's own `COUNTDOWN` event with a future deadline
- **THEN** the app SHALL resume the countdown and SHALL NOT present it as sent

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

