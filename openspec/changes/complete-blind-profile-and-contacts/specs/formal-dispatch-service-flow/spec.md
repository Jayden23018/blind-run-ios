## MODIFIED Requirements

### Requirement: Blind runner profile and booking gate
The iOS app SHALL require a logged-in blind-runner user to select the blind role, complete the blind-runner profile, obtain backend-approved blind-runner identity verification, store between one and five emergency contacts with exactly one primary contact, grant location access, choose a start location through the voice-first guided booking flow, and choose an appointment time at least 30 minutes in the future before submitting a booking.

#### Scenario: Blind runner can submit booking after required gates
- **WHEN** a logged-in user has active role `BLIND`, a complete blind-runner profile, approved identity verification, one to five emergency contacts with exactly one primary contact, location permission, a start location, and an appointment time at least 30 minutes away
- **THEN** the app SHALL allow booking submission through `POST /api/orders`
- **AND** the booking UI SHALL guide the user through start point, appointment time, optional running needs, and review before submission
- **AND** the app SHALL navigate to the order status flow when the backend returns an order ID

#### Scenario: Booking is blocked without required gates
- **WHEN** the blind-runner user lacks profile completion, approved identity verification, a valid primary emergency contact, location permission, start location, or a valid appointment time
- **THEN** the app SHALL block `POST /api/orders`
- **AND** the app SHALL show and speak the first actionable missing requirement
- **AND** the guided booking repeat-status action SHALL include the blocking reason when the user asks to repeat the current state

#### Scenario: Booking keeps map and coordinate contracts
- **WHEN** the blind-runner user confirms a start point through current location or AMap POI search
- **THEN** the app SHALL preserve coordinates for `CreateOrderRequest`, map annotations, and release validation
- **AND** visual map confirmation SHALL remain auxiliary to textual and spoken start-point confirmation
- **AND** no new backend endpoint or draft-booking contract SHALL be required
