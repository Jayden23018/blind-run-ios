## ADDED Requirements

### Requirement: The Xinghuo page shows aggregate presence, never individual positions
The Xinghuo page SHALL render only aggregated cells (a grid-cell center plus a headcount) and aggregate counts. It SHALL NOT render or receive any individual user's coordinate, because repeated sampling of fuzzed individual points lets an observer recover the true position.

#### Scenario: Cells are drawn on the map
- **WHEN** the page renders the map
- **THEN** each cell SHALL be drawn as a small cluster of at most 12 stars scattered within 180 m of the cell center, so no star is drawn inside a neighbouring cell
- **AND** the scatter, size, brightness and twinkle rhythm SHALL be derived deterministically from the cell id alone, so the same cell looks the same on every render and no position beyond the cell center is implied
- **AND** volunteer cells SHALL be four-point stars and runner cells SHALL be dots with a ring, so the two are distinguishable by shape without relying on color

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

### Requirement: Maps follow the system appearance, except the Xinghuo page
Every map in the app other than the Xinghuo page SHALL use the night base map style in dark appearance and the standard style in light appearance. The Xinghuo page SHALL always render as a night sky regardless of the system appearance, because glowing stars are not visible on a light base map; the tab bar and every other page SHALL keep following the system.

#### Scenario: The user switches appearance while a map is on screen
- **WHEN** the system appearance changes between light and dark
- **THEN** every map other than the Xinghuo page SHALL switch its base map style to match

#### Scenario: The Xinghuo page in light appearance
- **WHEN** the system appearance is light and the Xinghuo page is shown
- **THEN** the page SHALL render with the night base map, hidden place labels, and the Xinghuo night palette

### Requirement: The map on the Xinghuo page can be dragged freely
The page overlay SHALL leave the area between the top statistics and the bottom card free of touch-receiving views, and the map SHALL NOT be pulled back to its center by unrelated view updates; it SHALL return to the user only when the user asks for it.

#### Scenario: The user drags the map, then footprints finish loading
- **WHEN** the user has dragged the map away and the page state then changes
- **THEN** the map SHALL stay where the user left it

### Requirement: Xinghuo animations honour Reduce Motion
Stars SHALL light up outward from the user and twinkle, the user marker SHALL pulse, and footprints SHALL carry a moving light, unless the system Reduce Motion setting is on, in which case none of these animations SHALL run and every star SHALL appear immediately at a steady brightness.

#### Scenario: Reduce Motion is turned on while the page is open
- **WHEN** the user turns on Reduce Motion with the Xinghuo page on screen
- **THEN** every running star, ring and footprint animation SHALL stop
