## ADDED Requirements

### Requirement: Completion page shows star-level progress
After a volunteer finishes an escort, the completion page SHALL show the national star-level progress below the completion card, fetched when the page appears so that it includes the run just finished. When the achievements request fails, the progress card SHALL NOT be shown and the completion page SHALL remain fully usable.

#### Scenario: Achievements load
- **WHEN** the order is `COMPLETED` and `GET /api/volunteer/achievements` succeeds
- **THEN** the completion page SHALL show the star level, a progress bar, and the remaining-hours sentence, readable as one VoiceOver element

#### Scenario: Achievements fail
- **WHEN** the achievements request fails
- **THEN** no progress card and no error SHALL appear on the completion page

### Requirement: Meet panel hides the direction dial without a direction
On the meet panel, the app SHALL NOT draw the direction dial when no relative direction is available, so the ring action moves up instead of an empty circle occupying the screen.

#### Scenario: No direction yet
- **WHEN** the order is `DRIVER_ARRIVED` and the relative direction to the runner is unknown
- **THEN** the direction dial SHALL NOT be shown and the ring button SHALL be the first action in the meet section
