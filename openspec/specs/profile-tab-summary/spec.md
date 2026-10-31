# profile-tab-summary Specification

## Purpose
Defines the root page of the bottom 「我的」 tab for both roles: its title and the personal summary card at the top (runner: runs and distance this month; volunteer: completed runs and service hours). The settings list reached from the volunteer home gear keeps the title 「设置」 and shows no card.
## Requirements
### Requirement: Profile tab root is titled 我的 and opens with a personal summary
The root page of the bottom 「我的」 tab SHALL be titled 「我的」 for both roles and SHALL begin with a personal summary card when its data loads. The same settings list reached from the volunteer home gear (labelled 「设置」) SHALL keep the title 「设置」 and SHALL NOT show the card.

#### Scenario: Runner opens the tab
- **WHEN** a runner opens the 「我的」 tab and the current month's run records load
- **THEN** the page SHALL be titled 「我的」 and SHALL show the same monthly sentence as the records tab
- **AND** opening the tab SHALL NOT trigger a spoken announcement

#### Scenario: Volunteer opens the tab
- **WHEN** a volunteer opens the 「我的」 tab and achievements load
- **THEN** the page SHALL show completed escorts and total service hours, and tapping the card SHALL open the service recognition page

#### Scenario: Summary data fails
- **WHEN** the summary request fails
- **THEN** the card SHALL NOT be shown and the settings list SHALL remain usable

