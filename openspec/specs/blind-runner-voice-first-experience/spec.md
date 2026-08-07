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
- **THEN** the map SHALL be placed after the current state, next action, and repeat-status controls in VoiceOver traversal
- **AND** the map SHALL have an accessibility label that identifies it as auxiliary visual confirmation
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
