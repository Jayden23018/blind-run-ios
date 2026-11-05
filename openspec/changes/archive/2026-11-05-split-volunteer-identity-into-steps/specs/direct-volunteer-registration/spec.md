## MODIFIED Requirements

### Requirement: Volunteer registration uses two user-facing steps
The iOS client SHALL present volunteer registration as an intro page followed by three steps: identity (name, ID card number, phone), running experience (optional, skippable), and native face verification. The client SHALL submit the identity and experience fields in one existing basic-info request, and SHALL NOT require training progress or quiz completion.

#### Scenario: Registration flow is displayed
- **WHEN** a volunteer opens an incomplete registration flow at the basic-info step
- **THEN** the client SHALL first show an intro page that lists the three steps
- **AND** the intro page SHALL offer a start action and an action to verify with uploaded identity materials instead of the face
- **AND** the client SHALL NOT display course, progress, or quiz controls
- **AND** the client SHALL NOT call volunteer training endpoints

#### Scenario: Identity step is incomplete
- **WHEN** the volunteer is on step 1 and name, ID card number, or phone is missing or invalid
- **THEN** the step header SHALL read “第 1 步，共 3 步”
- **AND** the next action SHALL be disabled
- **AND** the client SHALL show which fields are still missing below the next action

#### Scenario: Experience step is submitted or skipped
- **WHEN** the volunteer taps next or skip on step 2
- **THEN** the client SHALL ask for the separate identity and face consent if it has not been recorded
- **AND** after consent the client SHALL submit name, phone, ID card, running experience, guided-before, and emergency experience in one `POST /api/volunteer/registration/step1` request
- **AND** skip SHALL NOT clear fields the volunteer has already entered

#### Scenario: Volunteer chose identity materials on the intro page
- **WHEN** the volunteer tapped the identity-materials action on the intro page and the basic-info submission moves registration to face verification
- **THEN** the client SHALL call the existing face-verification decline endpoint instead of announcing face verification
- **AND** the client SHALL show the existing alternative-path landing page with the upload entry
