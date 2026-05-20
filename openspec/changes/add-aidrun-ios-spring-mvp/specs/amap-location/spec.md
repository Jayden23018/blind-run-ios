## ADDED Requirements

### Requirement: iOS app uses real map and real location

The iOS app MUST integrate 高德地图 to display a real map, current location, and order start marker.

#### Scenario: Order marker displayed
- **WHEN** an order has a start coordinate
- **THEN** the map screen shows a marker at the order start point

### Requirement: Location permission is required for core flows

The iOS app MUST require location permission before blind runner booking and volunteer distance-based order viewing or accepting.

#### Scenario: Blind runner denies location
- **WHEN** a blind runner denies location permission and tries to create a booking
- **THEN** the app blocks booking and shows a location permission prompt

#### Scenario: Volunteer denies location
- **WHEN** a volunteer denies location permission and tries to view or accept nearby orders by distance
- **THEN** the app blocks the distance-based flow and shows a location permission prompt

### Requirement: Distance sorting is performed on iOS

The iOS app MUST calculate distance from volunteer current location to order start coordinates and sort available orders locally.

#### Scenario: Available orders returned unsorted
- **WHEN** the backend returns matching orders
- **THEN** the iOS volunteer list sorts them by calculated distance

### Requirement: Demo fallback coordinates are available

The iOS app MUST provide default test coordinates to keep simulator demos usable when device location cannot be obtained.

#### Scenario: Simulator has no location fix
- **WHEN** the simulator cannot provide a usable location
- **THEN** the app can use demo coordinates while still explaining that real location permission is required
