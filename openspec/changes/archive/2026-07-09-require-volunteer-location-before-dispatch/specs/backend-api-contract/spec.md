## MODIFIED Requirements

### Requirement: Volunteer dispatch requires recent WebSocket location

The canonical integration contract MUST require volunteers to connect `/ws/volunteer` and send a `LOCATION_UPDATE` before they can receive order dispatches or respond to dispatched orders.

#### Scenario: Volunteer becomes eligible for dispatch
- **WHEN** a volunteer is available and online
- **AND** the volunteer sends `{"type":"LOCATION_UPDATE","lat":number,"lng":number}` over `/ws/volunteer`
- **AND** the reported location is within 10 km of an order start point
- **THEN** the backend may include the order in `/api/orders/available` or send `NEW_ORDER`

#### Scenario: Volunteer responds before dispatch eligibility
- **WHEN** a volunteer sends `POST /api/orders/{id}/respond`
- **AND** the order has not been dispatched to that volunteer
- **THEN** the backend returns a business error such as `ORDER_DISPATCH_MISMATCH`
