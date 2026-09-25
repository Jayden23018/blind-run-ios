## MODIFIED Requirements

### Requirement: Completed summary uses the blind track as the run route
After an associated order is `COMPLETED`, the app SHALL fetch the typed track response and present the blind-runner track and statistics as the primary run summary. The full-screen route view SHALL be the role's post-run detail page (capabilities `volunteer-run-record-detail` and `runner-run-record-detail`), fed by the run record instead of the track response.

#### Scenario: Completed track is available
- **WHEN** `GET /api/orders/{id}/track` returns blind track points and statistics
- **THEN** the map SHALL render the blind polyline titled "本次路线"
- **AND** the primary summary SHALL show blind distance, duration, and average pace
- **AND** visible text, VoiceOver, TTS, and repeat-status output SHALL provide equivalent information

#### Scenario: Track data is partial or empty
- **WHEN** the blind track or one or more statistics are absent
- **THEN** the app SHALL present an honest partial/unavailable state
- **AND** it SHALL NOT substitute demo points or fabricate statistics

#### Scenario: Volunteer opens the full-screen route
- **WHEN** the signed-in volunteer activates the full-screen route link in the completed summary
- **THEN** the app SHALL open the volunteer post-run detail page for that order
- **AND** it SHALL NOT open the track-based route replay

#### Scenario: Runner opens the full-screen route
- **WHEN** the signed-in blind runner activates the full-screen route link in the completed summary
- **THEN** the app SHALL open the runner post-run detail page for that order
- **AND** no track-based route replay SHALL exist
