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
The blind-runner home SHALL expose a single booking action, and that action SHALL open the slot-based booking page. No form or voice booking path SHALL be reachable from it.

#### Scenario: Home exposes one booking action
- **WHEN** a logged-in blind-runner user without an active order opens the home screen
- **THEN** exactly one booking action SHALL be present
- **AND** activating it SHALL open the slot-based booking page

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

### Requirement: Free-text fields outside booking offer dictation
The runner message, the review comment, the report detail and the support ticket SHALL each offer a dictation button below the text field. Dictation SHALL use the device speech framework and SHALL NOT send the text to the backend language model.

#### Scenario: Dictating into an empty field
- **WHEN** the field is empty and the user dictates "我穿红色外套"
- **THEN** the field SHALL contain "我穿红色外套"
- **AND** the app SHALL announce "已填入：我穿红色外套"

#### Scenario: Dictating into a field that already has text
- **WHEN** the field contains "东门见" and the user dictates "我穿红色外套"
- **THEN** the field SHALL contain "东门见我穿红色外套"
- **AND** the text typed before recording SHALL NOT be replaced

#### Scenario: Nothing was recognized
- **WHEN** recording ends without recognized text
- **THEN** the field SHALL keep its previous text
- **AND** the app SHALL NOT announce "已填入"

#### Scenario: The user edits the field while recording
- **WHEN** recording is running and the user changes the text in the field
- **THEN** the app SHALL stop recording and SHALL NOT overwrite the user's edit with later recognition results
- **AND** the app SHALL NOT announce "已填入"

#### Scenario: Submitting while recording
- **WHEN** the user submits or saves while recording is running for that field
- **THEN** the app SHALL stop recording before it submits, so the microphone does not keep writing into submitted text

#### Scenario: Keyboard input still works
- **WHEN** speech recognition is not authorized or not available
- **THEN** the text field SHALL still accept keyboard input

