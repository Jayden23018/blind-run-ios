## ADDED Requirements

### Requirement: Blind runner flow supports VoiceOver

The iOS app MUST provide VoiceOver labels and hints for blind runner key buttons, inputs, and status text.

#### Scenario: VoiceOver user creates booking
- **WHEN** VoiceOver is enabled on a blind runner device
- **THEN** the user can understand and operate login, profile, booking, status, cancel, emergency, confirm-start, and rating controls

### Requirement: Blind runner UI uses large simple controls

The iOS app MUST use large, clear blind runner primary actions with a minimum 64pt button height.

#### Scenario: Primary action visible
- **WHEN** a blind runner page presents its main action
- **THEN** the action has a large touch target and clear text in light and dark mode

### Requirement: TTS announces major flow nodes

The iOS app MUST use `AVSpeechSynthesizer` to announce entering blind home, order submitted, matching, accepted, arrived, confirm-start prompt, service started, completed, emergency, and errors.

#### Scenario: Volunteer arrives
- **WHEN** polling observes an order state change to `arrived`
- **THEN** the blind runner app speaks that the volunteer has arrived and asks the runner to confirm service start

### Requirement: Repeat current status is available

Each key blind runner page MUST provide a “重复当前状态” action that repeats the latest meaningful status.

#### Scenario: User requests repeat
- **WHEN** the blind runner taps “重复当前状态”
- **THEN** the app speaks the current status without changing order state

### Requirement: Speech input is limited to text fields

The iOS app MUST use the Speech framework only for text fields such as location description, route notes, remarks, and optional summary.

#### Scenario: Speech input fails
- **WHEN** speech recognition fails for a text field
- **THEN** the app shows an error and allows keyboard input
