## ADDED Requirements

### Requirement: The launch disclosure names motion data before it is collected
The app SHALL state, in the first-launch disclosure, that step count, cadence and climbed altitude are recorded from the phone's motion sensor during a run service, what they are used for, and who can see them, because this is a category of personal information added after the previous disclosure version and a consent recorded against the old text does not cover it (PIPL Art. 14).

#### Scenario: Motion data is described as its own disclosure item
- **WHEN** the launch disclosure is presented
- **THEN** it SHALL contain a separate item naming step count, cadence and climbed altitude, so a screen-reader user hears it as its own focus rather than buried in another sentence
- **AND** that item SHALL say the data appears only in the user's own run record and not to the other party
- **AND** that item SHALL say declining the motion permission does not affect the run service

#### Scenario: A device consented under the previous disclosure text
- **WHEN** a device has a recorded launch consent for the previous disclosure version
- **THEN** the launch disclosure SHALL be shown again, because the recorded consent was given for text that did not name motion data

### Requirement: The built-in privacy policy lists motion data and how to turn it off
The built-in privacy policy fallback SHALL list motion data among the collected items, SHALL explain that the Motion & Fitness permission can be turned off in system settings and what is lost when it is, and SHALL say that deleting the account deletes the run records, so that it matches the online policy v1.2 rather than contradicting it.

#### Scenario: Reviewer reads the built-in policy
- **WHEN** the built-in privacy policy is displayed
- **THEN** it SHALL mention step count and the Motion & Fitness permission
