## MODIFIED Requirements

### Requirement: Voice feedback is concise and repeatable
The iOS blind-runner flow SHALL provide coherent TTS and VoiceOver feedback for booking without creating speech spam.

#### Scenario: Step summary changes
- **WHEN** the user changes a selection on the booking page
- **THEN** the app SHALL make the current value available through visible text and repeat-status speech
- **AND** the app SHALL NOT automatically speak long summaries after every keystroke or picker adjustment

#### Scenario: Repeat status during booking
- **WHEN** the user activates "重复当前状态" during booking
- **THEN** the app SHALL speak the current selection and the next expected action
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
- **WHEN** the blind-runner booking page is displayed
- **THEN** the screen SHALL emphasize one primary task
- **AND** optional fields SHALL NOT obscure the required next action
- **AND** dense table-like layouts SHALL NOT be used for required blind-runner task completion
