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
The iOS blind-runner booking flow SHALL guide the user through start point, appointment time, optional running needs, and review before creating an order.

#### Scenario: Confirm start point
- **WHEN** the blind runner starts booking
- **THEN** the first booking step SHALL present the current resolved start point as text and speech-ready summary
- **AND** the user SHALL be able to keep the default current location or search for a different AMap POI
- **AND** speech input for start-place search SHALL remain field-level and SHALL auto-search after recognition completes with non-empty text

#### Scenario: Confirm appointment time
- **WHEN** the blind runner proceeds to appointment time selection
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

