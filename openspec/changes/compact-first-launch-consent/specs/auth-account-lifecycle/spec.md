## ADDED Requirements

### Requirement: The launch disclosure leads with a summary and keeps the decision controls reachable
The first-launch disclosure screen SHALL present a short summary of what is collected and why, with the agree and decline controls reachable without scrolling, and SHALL keep the full itemised disclosure one navigation step away rather than removing it.

#### Scenario: Default text size
- **WHEN** the launch disclosure screen is shown at a non-accessibility text size
- **THEN** the agree and decline controls SHALL be visible without scrolling
- **AND** the summary SHALL name the phone number, location, voice, ID card number, face and vision-status categories or point to where they are itemised

#### Scenario: Accessibility text size
- **WHEN** the text size is an accessibility size
- **THEN** the controls MAY be placed at the end of the scrollable content so they do not occupy most of the screen

#### Scenario: Reading the itemised disclosure
- **WHEN** the user opens the full collection list from the launch screen
- **THEN** every item of the itemised disclosure SHALL be shown unchanged and SHALL be an independent VoiceOver focus
- **AND** leaving that page SHALL NOT record consent
