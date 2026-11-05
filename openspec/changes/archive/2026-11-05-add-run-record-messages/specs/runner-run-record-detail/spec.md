## ADDED Requirements

### Requirement: Runner reads and hears the volunteer's messages
When the record has volunteer messages, the page SHALL show a "X的留言" section between "每一公里" and "路线" with every volunteer message as text and a "朗读留言" button. The button SHALL speak the messages through the same player as the narration and the sound route: starting it SHALL stop the other two, activating it again SHALL stop it, and VoiceOver focus leaving it SHALL pause it. The page SHALL NOT offer a reply control in this change.

#### Scenario: No volunteer message
- **WHEN** the record has no message from the volunteer
- **THEN** the section SHALL NOT be shown

#### Scenario: Narration running
- **WHEN** "朗读留言" is activated while the narration or the sound route is playing
- **THEN** that playback SHALL stop and the messages SHALL be spoken
