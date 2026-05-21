## ADDED Requirements

### Requirement: Volunteer must be approved and available to accept orders

The system MUST require volunteer nickname, phone, Mock verification approval, admin review approval, and `isAvailable = true` before accepting an order.

#### Scenario: Volunteer not approved
- **WHEN** an unapproved volunteer attempts to accept an order
- **THEN** the backend returns `VOLUNTEER_NOT_APPROVED`

#### Scenario: Volunteer unavailable
- **WHEN** an approved volunteer with `isAvailable = false` attempts to accept an order
- **THEN** the backend returns `VOLUNTEER_NOT_AVAILABLE`

### Requirement: Mock certification approves volunteer

The system MUST provide a Mock certification action that sets both `verificationStatus` and `adminReviewStatus` to `approved`.

#### Scenario: Mock certification completed
- **WHEN** a volunteer completes the Mock certification action
- **THEN** the volunteer profile becomes eligible for accepting orders after availability is enabled

### Requirement: Volunteers see non-sensitive order data before accepting

The system MUST show available volunteers blind runner nickname, start location, appointment time, optional destination or route description fields, and remarks before accepting, while hiding phone and emergency contacts.

#### Scenario: Available order list
- **WHEN** a volunteer views available orders
- **THEN** the response contains `matching` orders without blind runner phone or emergency contact

### Requirement: Accepted volunteer can progress service

The system MUST allow the accepted volunteer to mark arrival and complete service after the blind runner confirms start.

#### Scenario: Volunteer service flow
- **WHEN** an accepted volunteer marks arrived, the blind runner confirms start, and the volunteer completes service
- **THEN** the order reaches `completed`
