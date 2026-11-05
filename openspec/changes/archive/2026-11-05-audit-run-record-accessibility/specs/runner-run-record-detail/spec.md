## ADDED Requirements

### Requirement: Pace colour on the route has a legend
When the map is shown (at the top with VoiceOver off, or in the "路线" section) and the route is coloured by pace, it SHALL show the same "快 ▬ 慢" legend as the volunteer detail, hidden from VoiceOver. This holds until the P1 high-contrast map replaces the pace colouring.

#### Scenario: VoiceOver off
- **WHEN** VoiceOver is off and the record has pace samples
- **THEN** the map at the top SHALL show the legend

### Requirement: Listen is one swipe after the header in every state
The "听这次跑步" control SHALL directly follow the header in VoiceOver order whenever a narration exists, including when the record has no usable route. The "这次没有记录到完整路线" notice SHALL come after it.

#### Scenario: Insufficient track
- **WHEN** the record status is `INSUFFICIENT_TRACK` and a narration exists
- **THEN** one swipe right from the header SHALL land on "听这次跑步"

### Requirement: Focus moving away cancels a route that is still rendering
If VoiceOver focus moves away from the sound-route control while the route is still being rendered, playback SHALL NOT start when rendering finishes.

#### Scenario: Focus moves during rendering
- **WHEN** the user starts the sound route and moves focus to another element before it starts playing
- **THEN** the player SHALL return to idle and stay silent

