## ADDED Requirements

### Requirement: The Xinghuo page shows aggregate presence, never individual positions
The Xinghuo page SHALL render only aggregated cells (a grid-cell center plus a headcount) and aggregate counts. It SHALL NOT render or receive any individual user's coordinate, because repeated sampling of fuzzed individual points lets an observer recover the true position.

#### Scenario: Cells are drawn on the map
- **WHEN** the page renders the map
- **THEN** each marker SHALL be placed at a cell center, sized by the cell's headcount tier
- **AND** volunteer cells SHALL be four-point stars and runner cells SHALL be dots with a halo, so the two are distinguishable by shape without relying on color

#### Scenario: A blind runner opens the page
- **WHEN** the active role is the blind runner
- **THEN** the page SHALL show volunteer cells only and SHALL NOT show other blind runners' cells

#### Scenario: A volunteer opens the page
- **WHEN** the active role is the volunteer
- **THEN** the page SHALL show both volunteer cells and blurred runner cells

### Requirement: The page leads with one spoken summary of aggregate counts
The first accessibility element SHALL be a one-sentence summary of the aggregate counts, and the "hear the stars" control SHALL speak that same sentence. The summary SHALL NOT include place names, directions, or per-event updates.

#### Scenario: Volunteers are online
- **WHEN** the online volunteer count is greater than zero
- **THEN** the summary SHALL state the count in the region

#### Scenario: Nobody is online
- **WHEN** the online volunteer count is zero
- **THEN** the summary SHALL say that no volunteer is currently online rather than presenting a fabricated number

### Requirement: Today's footprints come from the user's own completed runs
The footprint layer SHALL draw only routes of the user's own orders that completed today, using the existing order track endpoint.

#### Scenario: Track loading fails
- **WHEN** loading the order list or a track fails for a reason other than task cancellation
- **THEN** the page SHALL show a visible notice that footprints could not be loaded instead of silently rendering nothing

### Requirement: Phase one is debug-only
Until the backend aggregation endpoint exists, the Xinghuo tab SHALL be compiled only into debug builds and SHALL display a visible demo-data label.

#### Scenario: Release build
- **WHEN** the app is built in the Release configuration
- **THEN** neither role's tab bar SHALL contain the Xinghuo tab

### Requirement: Maps follow the system appearance
Every map in the app SHALL use the night base map style in dark appearance and the standard style in light appearance, and custom markers and footprint lines SHALL be redrawn when the appearance changes.

#### Scenario: The user switches appearance while a map is on screen
- **WHEN** the system appearance changes between light and dark
- **THEN** the base map style, Xinghuo markers, and footprint lines SHALL all switch to the matching palette
