## ADDED Requirements

### Requirement: Spoken extra needs are recorded verbatim
The app SHALL record a blind runner's spoken extra needs as the user's own words. It SHALL NOT summarise, paraphrase, shorten, or otherwise rewrite them before storing or displaying them, because the user cannot see the screen and therefore cannot verify any rewriting the app performs.

#### Scenario: Free-text extra needs are captured from the utterance
- **WHEN** a blind runner states extra needs inside the single booking utterance
- **THEN** the app SHALL carry the free-text extra needs forward as a verbatim span of the user's transcript
- **AND** it SHALL NOT substitute a generated summary, a normalised phrasing, or a canned category label for that text

#### Scenario: Parser returns rewritten text
- **WHEN** the parsing response returns free-text extra needs that are not a substring of the submitted transcript
- **THEN** the app SHALL discard that text rather than store it
- **AND** the booking SHALL proceed with no free-text extra needs rather than fail

#### Scenario: The utterance is long enough that the parser silently stops extracting
- **WHEN** a blind runner's utterance is longer than the length above which the parsing service stops using its language model and falls back to patterns alone
- **THEN** the app SHALL say, before it reads the order back, that it could only keep the keywords and that the destination and the extra needs may be missing
- **AND** that statement SHALL name the way out, namely restating the request more briefly
- **AND** the app SHALL NOT silently truncate the utterance, and SHALL NOT present the resulting order as though nothing was dropped

### Requirement: Extra needs are read back before the order is created
The app SHALL read back every extra need it extracted, so that an extraction error is discoverable by ear before the order exists.

#### Scenario: Structured extra needs were extracted
- **WHEN** the app reads the order back and it extracted a guide-dog flag or a pace preference from the utterance
- **THEN** the read-back SHALL name each extracted value explicitly
- **AND** it SHALL NOT announce extra needs that were not extracted, so the read-back stays short enough to be heard through

#### Scenario: Nothing was extracted for an optional slot
- **WHEN** the utterance mentions no guide dog and no pace preference
- **THEN** the app SHALL NOT ask for them and SHALL NOT block confirmation on them
- **AND** the order SHALL be created without those fields so the backend falls back to the runner's profile defaults

#### Scenario: Guide-dog was not mentioned
- **WHEN** the parse result carries no guide-dog value for this run
- **THEN** the app SHALL omit the per-run guide-dog field from the create-order request rather than send `false`
- **AND** it SHALL NOT treat "not mentioned" as "not bringing the dog", because that value feeds dispatch hard-filtering

### Requirement: Sensitive free-text extra needs are hidden until an order is accepted
No free text a blind runner wrote or spoke SHALL be shown to a volunteer who has not accepted the order. This covers every free-text field on the order, not only the one that carries voice-captured needs — the risk follows the field's type, not its intended use, and the app cannot tell before display which kind of sentence a user wrote in a given box. Dispatch is serial and the open-order list is browsable, so an order reaches several volunteers who never serve it.

#### Scenario: Dispatch prompt before accepting
- **WHEN** a volunteer is shown a dispatch prompt for an order they have not accepted
- **THEN** the app SHALL NOT render free-text extra needs anywhere in that prompt
- **AND** this SHALL hold regardless of whether the transport still carries the field

#### Scenario: Browsing an order that is still awaiting a match
- **WHEN** any volunteer opens an order from the list of orders still awaiting a match
- **THEN** the app SHALL NOT render any blind-runner free text on that screen or in its accessibility labels
- **AND** this SHALL hold for every free-text field on the order, including ones whose intended use looks harmless

#### Scenario: Order is accepted
- **WHEN** a volunteer has accepted the order and is therefore a participant in it
- **THEN** the app SHALL show the free-text extra needs verbatim in the order detail

#### Scenario: The accepting volunteer withdraws
- **WHEN** the volunteer who accepted an order cancels it and the order returns to matching
- **THEN** that volunteer SHALL no longer be shown the blind runner's free text, because they are no longer a participant

#### Scenario: An unrecognised order status arrives
- **WHEN** the order carries a status this client does not recognise
- **THEN** the app SHALL withhold the free text
- **AND** this SHALL be the opposite default from other unknown-status handling, which keeps the order visible and pollable

#### Scenario: Free text is captured by voice before the disclosure boundary exists
- **WHEN** the backend has not yet provided a channel that withholds free-text extra needs until acceptance
- **THEN** the app SHALL NOT place voice-captured free text into any field that is disclosed before acceptance
- **AND** the runner SHALL be told audibly that the note was not attached, rather than the app silently dropping it

### Requirement: Structured matching conditions stay visible before acceptance
Guide-dog carriage and pace preference SHALL remain visible to candidate volunteers before acceptance. Their value spaces are closed and can be judged safe in advance, and both are the basis on which a volunteer decides whether they can serve this run at all.

#### Scenario: Dispatch prompt shows matching conditions
- **WHEN** a volunteer is shown a dispatch prompt for an order carrying a guide-dog flag or a pace preference
- **THEN** the app SHALL show those values
- **AND** hiding them SHALL NOT be treated as a way to satisfy the free-text disclosure rule, because doing so forces volunteers to accept blind and pushes the cost of a later cancellation onto the runner

#### Scenario: A new extra-need field is added later
- **WHEN** a new extra-need field is introduced
- **THEN** its disclosure boundary SHALL be decided by whether its value space is closed and every possible value is safe to show a stranger
- **AND** a field with an open value space SHALL default to being hidden until acceptance
