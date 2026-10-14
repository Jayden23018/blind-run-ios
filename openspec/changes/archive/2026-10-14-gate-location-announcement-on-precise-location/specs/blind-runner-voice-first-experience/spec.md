## MODIFIED Requirements

### Requirement: Location announcement falls back to the server and states its age
The app SHALL answer "播报我的位置" from the device fix first and, when that yields no place, from `GET /api/orders/{id}/location/address`, stating how old the server position is when it is older than 15 seconds. The volunteer's emergency alert SHALL use the same endpoint for the runner's place when it has no coordinate or local reverse geocoding fails. When the system "Precise Location" setting is off for the app, the app SHALL NOT announce any place derived from a coordinate, because both the device fix and the server copy are only an area representative point up to several kilometres away.

#### Scenario: Device has no usable place
- **WHEN** the runner asks for their location, precise location is on, and the device fix or its reverse geocode yields nothing
- **THEN** the app SHALL request the endpoint and read the address, else the coordinates, else the "暂时定位不到" sentence
- **AND** when `ageSeconds` is greater than 15 it SHALL append "这是N秒前的位置。"
- **AND** when `ageSeconds` is null it SHALL NOT mention an age

#### Scenario: Server request fails
- **WHEN** the endpoint request fails
- **THEN** the app SHALL read the "暂时定位不到" sentence rather than stay silent

#### Scenario: Precise location is off
- **WHEN** the runner asks for their location while precise location is off
- **THEN** the app SHALL NOT reverse geocode the device fix and SHALL NOT request the endpoint
- **AND** it SHALL read "「精确位置」已关闭，只能拿到大致位置，可能偏差几公里，所以念不出你的准确位置。请直接拨打120或110，说明你周围的情况；跑完后可在系统设置里为助盲跑打开「精确位置」。"
- **AND** it SHALL NOT trigger a system location prompt

#### Scenario: Precise location is on
- **WHEN** the runner asks for their location while precise location is on and the device has a real fix
- **THEN** the app SHALL reverse geocode the fix and read "你现在在<地名>附近。"

#### Scenario: Volunteer alert without a coordinate
- **WHEN** the volunteer alert has no coordinate or local reverse geocoding fails
- **THEN** the place line SHALL show the server address or coordinates with the age notice, or "暂时收不到他的位置" when there is neither
