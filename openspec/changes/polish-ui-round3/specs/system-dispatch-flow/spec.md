## ADDED Requirements

### Requirement: Volunteer intro-call page shows the deadline on its own line
While the intro call is active, the volunteer intro-call page SHALL show the window end time as its own line in body text, using the same relative-day wording as the invitation page (for example 「今天 23:51 前完成通话确认」). The 「不合适」 action SHALL NOT be styled as destructive.

#### Scenario: Active intro call
- **WHEN** a volunteer opens the intro-call page and `windowEndsAt` is today at 23:51
- **THEN** a line reading 「今天 23:51 前完成通话确认」 SHALL appear below the header
- **AND** the 「不合适」 button SHALL be an outlined secondary button in the primary colour

#### Scenario: Intro call already settled
- **WHEN** the intro call is matched or closed
- **THEN** the deadline line SHALL NOT be shown
