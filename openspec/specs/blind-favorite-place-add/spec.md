# blind-favorite-place-add Specification

## Purpose
TBD - created by archiving change reduce-blind-secondary-forms. Update Purpose after archive.
## Requirements
### Requirement: Adding a favorite start place is its own page
Choosing "添加常用地点" on the default start place page SHALL push a dedicated page, not the booking form. The page SHALL offer, in order: a "使用当前定位" row, a place search field with Apple speech input, and the places the runner started recent completed runs from.

#### Scenario: Runner chooses the current location
- **WHEN** the runner taps "使用当前定位"
- **THEN** the default start place SHALL become the current location, no favorite SHALL be added, and the app SHALL return home and speak the result

#### Scenario: Runner picks a search result
- **WHEN** the runner searches and taps a result
- **THEN** the place SHALL be saved as a favorite and as the default start place, and the app SHALL return home and speak the place name

#### Scenario: Runner picks a recent place
- **WHEN** completed orders with a start address and coordinates exist
- **THEN** up to five distinct start places SHALL be listed newest first, each with the date it was used
- **AND** tapping one SHALL save it as a favorite and as the default start place

#### Scenario: No completed runs
- **WHEN** no completed order has a usable start place, or loading orders fails
- **THEN** the recent group SHALL NOT be shown, and the rest of the page SHALL work

