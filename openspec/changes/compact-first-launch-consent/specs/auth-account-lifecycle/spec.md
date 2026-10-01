## ADDED Requirements

### Requirement: The launch disclosure is a centred dialog that leaves the decision controls reachable
The first-launch disclosure SHALL be presented as a dialog card centred over a dimmed backdrop rather than as a full page, with a short summary, entry points to the full texts, and equal-sized decline (left) and agree (right) controls. The backdrop SHALL NOT render any screen that collects personal information.

#### Scenario: Default text size
- **WHEN** the launch disclosure is shown at a non-accessibility text size
- **THEN** the dialog SHALL be visibly smaller than the screen on both axes, with backdrop showing around it
- **AND** the decline control SHALL be to the left of the agree control, both reachable without scrolling
- **AND** the summary SHALL name the phone number, location, voice, ID card number, face and vision-status categories or point to where they are itemised

#### Scenario: Accessibility text size
- **WHEN** the text size is an accessibility size
- **THEN** the controls MAY stack vertically and the dialog content MAY scroll inside a card capped below the screen height, so the card never exceeds the screen

#### Scenario: Reading the itemised disclosure
- **WHEN** the user opens the full collection list from the dialog
- **THEN** every item of the itemised disclosure SHALL be shown unchanged and SHALL be an independent VoiceOver focus
- **AND** leaving that page SHALL NOT record consent
