## ADDED Requirements

### Requirement: Nothing is collected before the launch disclosure is accepted
The app SHALL present a disclosure-and-consent screen as the first visible screen on a fresh install, ahead of every routed destination including the login screen, because a phone number is personal information and asking for it before disclosure is collection without consent (PIPL Art. 14; App Store Review 5.1.1).

#### Scenario: Fresh install opens the app
- **WHEN** the app launches with no recorded launch consent
- **THEN** the disclosure screen SHALL be shown instead of any routed destination
- **AND** the login screen SHALL NOT be reachable until consent is recorded

#### Scenario: User accepts the disclosure
- **WHEN** the user activates the agree control
- **THEN** consent SHALL be recorded before routing resumes
- **AND** the recorded consent SHALL survive relaunch, so the screen is shown once rather than every cold start

#### Scenario: User declines the disclosure
- **WHEN** the user activates the decline control
- **THEN** the app SHALL state the consequence and remain on the disclosure screen
- **AND** the app SHALL NOT terminate itself, because a closing app reads as a broken app to someone who cannot see the screen
- **AND** the full privacy policy and user agreement SHALL remain reachable from that screen so the user can decide with the text in hand

#### Scenario: Viewing the screen without acting on it
- **WHEN** the user reads or leaves the disclosure screen without activating the agree control
- **THEN** consent SHALL NOT be recorded, because consent is an action rather than an exposure

### Requirement: Sensitive personal information is consented to separately at its collection point
The app SHALL obtain a separate consent immediately before submitting an ID card number or entering face liveness verification, and SHALL NOT send the request without it (PIPL Art. 29). Accepting the launch disclosure SHALL NOT satisfy this requirement, because a general consent does not cover sensitive categories.

#### Scenario: Blind runner submits identity verification for the first time
- **WHEN** the user activates submit on the identity verification screen with no recorded consent for that purpose
- **THEN** the disclosure screen for the ID card number SHALL be shown and no network request SHALL be sent
- **AND** the request SHALL be sent only after the user agrees

#### Scenario: Volunteer submits registration step one for the first time
- **WHEN** the user activates submit on the volunteer basic-information step with no recorded consent for that purpose
- **THEN** the disclosure SHALL name both the ID card number and the face liveness check that follows, because the next screen starts it

#### Scenario: The same person submits again
- **WHEN** a user who has already consented for that purpose submits again
- **THEN** the request SHALL be sent without repeating the full disclosure, because a disclosure the user learns to skip stops being a disclosure

#### Scenario: A different account signs in on the same device
- **WHEN** identity verification is submitted under a different user id
- **THEN** the previous account's consent SHALL NOT apply, because consent is given by a person and shared devices are common for blind users

#### Scenario: Disclosure wording changes
- **WHEN** the disclosure text for a purpose is edited
- **THEN** consents recorded against the previous wording SHALL NOT be treated as consent to the new wording

### Requirement: The in-app privacy text lists every category the app actually collects
While the backend returns no privacy policy URL, the built-in fallback text is what users and reviewers actually read, so it SHALL enumerate every collected category and SHALL identify the sensitive ones.

#### Scenario: Backend returns null legal links
- **WHEN** `GET /api/misc/legal-links` returns null for the privacy policy URL
- **THEN** the built-in text SHALL be shown and SHALL name the phone number, ID card name and number, location and route track, microphone and speech content, camera and face information, and emergency contact details
- **AND** it SHALL identify the ID card number, face information, and location track as sensitive personal information handled under a separate consent
