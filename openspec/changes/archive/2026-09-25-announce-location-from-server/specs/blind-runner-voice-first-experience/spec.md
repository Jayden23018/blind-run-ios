## ADDED Requirements

### Requirement: Location announcement falls back to the server and states its age
The app SHALL answer "播报我的位置" from the device fix first and, when that yields no place, from `GET /api/orders/{id}/location/address`, stating how old the server position is when it is older than 15 seconds. The volunteer's emergency alert SHALL use the same endpoint for the runner's place when it has no coordinate or local reverse geocoding fails.

#### Scenario: Device has no usable place
- **WHEN** the runner asks for their location and the device fix or its reverse geocode yields nothing
- **THEN** the app SHALL request the endpoint and read the address, else the coordinates, else the "暂时定位不到" sentence
- **AND** when `ageSeconds` is greater than 15 it SHALL append "这是N秒前的位置。"
- **AND** when `ageSeconds` is null it SHALL NOT mention an age

#### Scenario: Server request fails
- **WHEN** the endpoint request fails
- **THEN** the app SHALL read the "暂时定位不到" sentence rather than stay silent

#### Scenario: Volunteer alert without a coordinate
- **WHEN** the volunteer alert has no coordinate or local reverse geocoding fails
- **THEN** the place line SHALL show the server address or coordinates with the age notice, or "暂时收不到他的位置" when there is neither
