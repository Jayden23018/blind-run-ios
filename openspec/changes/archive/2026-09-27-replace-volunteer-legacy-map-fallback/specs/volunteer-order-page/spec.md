## MODIFIED Requirements

### Requirement: Order page switches in place by server status
The volunteer order page SHALL render one page whose content switches in place according to the order status returned by `GET /api/orders/{id}`, without pushing a new page. `SCHEDULED_CONFIRMED` and `PENDING_ACCEPT` SHALL render the "agreed" layout, `DRIVER_EN_ROUTE` the "departed" layout, `DRIVER_ARRIVED` the "arrived" layout, `COMPLETED` the completion layout, and a runner-initiated `CANCELLED` the runner-cancelled layout. `IN_PROGRESS` SHALL keep the existing running page. Before the first order detail arrives, after the first load fails, and for any status that none of the layouts above covers, the page SHALL render the order page navigation bar (back + help) over a plain status area, without a map and without any state-transition action.

#### Scenario: Status change keeps the same page
- **WHEN** the order moves from `DRIVER_EN_ROUTE` to `DRIVER_ARRIVED` while the page is open
- **THEN** the page SHALL switch to the arrived layout in place
- **AND** the navigation stack depth SHALL NOT change

#### Scenario: Unknown status does not blank the page
- **WHEN** the backend returns a status value the client does not recognise, or a status no layout covers (`PENDING_MATCH`, `PENDING_INTRO_CALL`, `REMATCHING`, `NO_VOLUNTEER`)
- **THEN** the page SHALL still render a navigation bar with the help entry and a readable status line
- **AND** the help entry SHALL offer local dialling only and SHALL NOT call `POST /api/emergency/trigger`
- **AND** the page SHALL NOT offer cancel, finish or any other state transition

#### Scenario: Order detail still loading
- **WHEN** the page opens and no order detail has arrived yet
- **THEN** the page SHALL show a loading indicator reading "正在获取订单状态" under the navigation bar with the help entry

#### Scenario: First load fails
- **WHEN** the first order detail request fails and the page holds no order
- **THEN** the page SHALL show a visible and spoken-readable message that loading failed and will be retried automatically
- **AND** polling SHALL continue so the page switches to the matching layout once a detail arrives
