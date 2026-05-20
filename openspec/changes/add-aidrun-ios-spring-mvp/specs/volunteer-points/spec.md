## ADDED Requirements

### Requirement: Completed service awards volunteer points

The system MUST award 100 points to the volunteer when an order reaches `completed`.

#### Scenario: Service completed
- **WHEN** a volunteer completes an `in_progress` order
- **THEN** the backend creates a volunteer points ledger entry with `pointsDelta = 100`

### Requirement: Volunteer can view service records

The system MUST provide volunteer service records containing service time, blind runner nickname, start location, service status, and earned points.

#### Scenario: View completed record
- **WHEN** a volunteer opens service records after completing a service
- **THEN** the completed service appears with 100 earned points

### Requirement: Points shop is display-only in MVP

The system MUST provide placeholder points shop items without exchange, inventory, payment, or fulfillment.

#### Scenario: View placeholder items
- **WHEN** a volunteer opens the points shop
- **THEN** the app displays placeholder items and no redemption action is required
