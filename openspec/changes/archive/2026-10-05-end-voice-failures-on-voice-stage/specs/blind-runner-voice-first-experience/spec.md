## ADDED Requirements

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
