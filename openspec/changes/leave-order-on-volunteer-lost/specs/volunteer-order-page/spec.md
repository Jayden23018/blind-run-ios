## ADDED Requirements

### Requirement: Volunteer leaves an order the server has taken away
When the server tells the volunteer that an order they had departed for has been handed to someone else, the volunteer order page SHALL leave that order and return to the dispatch home, and the home SHALL stop showing it as the current order. The event `ORDER_VOLUNTEER_LOST` carries no order id; it SHALL apply only when the order the volunteer holds is in `DRIVER_EN_ROUTE` or `DRIVER_ARRIVED`. The backend `ttsText` of that event SHALL be the only sentence spoken: neither the order page nor the home SHALL speak a status sentence for this order afterwards. The same SHALL happen when the event is received through reconnect catch-up. Independently, when the order page receives `REMATCHING` for its order and the volunteer did not request the cancellation, the page SHALL leave instead of staying on the loading fallback. Before leaving, open sheets and dialogs on the page SHALL close, and no request for that order SHALL be sent from the page. `ORDER_DEPARTURE_STALLED`, `ORDER_ARRIVAL_STALLED`, `REMATCHING_MID_RUN` and `SCHEDULED_DEPARTURE_GATE_MISSED` SHALL NOT trigger this behaviour.

#### Scenario: Volunteer-lost event while departed
- **WHEN** the order page holds an order in `DRIVER_EN_ROUTE` and `ORDER_VOLUNTEER_LOST` arrives, followed by `ORDER_STATUS_CHANGED` to `REMATCHING`
- **THEN** the page SHALL leave and the home SHALL no longer show the order
- **AND** only the event's `ttsText` SHALL be spoken

#### Scenario: Event received during catch-up
- **WHEN** `ORDER_VOLUNTEER_LOST` is returned by `/api/notifications/since` while the page holds an order in `DRIVER_ARRIVED`
- **THEN** the page SHALL leave in the same way

#### Scenario: Event does not apply to the running page
- **WHEN** the order page holds an order in `IN_PROGRESS` and `ORDER_VOLUNTEER_LOST` arrives
- **THEN** the page SHALL stay on the order

#### Scenario: Status change without the volunteer's own cancellation
- **WHEN** the order page holds an order in `DRIVER_EN_ROUTE`, the volunteer has not requested a cancellation, and `ORDER_STATUS_CHANGED` to `REMATCHING` arrives
- **THEN** the page SHALL leave

#### Scenario: Other safety events
- **WHEN** `ORDER_ARRIVAL_STALLED`, `ORDER_DEPARTURE_STALLED`, `REMATCHING_MID_RUN` or `SCHEDULED_DEPARTURE_GATE_MISSED` arrives while the page holds an order in `DRIVER_ARRIVED`
- **THEN** the page SHALL stay on the order
