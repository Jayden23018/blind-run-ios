## MODIFIED Requirements

### Requirement: Booking has exactly one entry point
The blind-runner home SHALL expose a single booking action, and that action SHALL open the slot-based booking page. No form or voice booking path SHALL be reachable from it.

#### Scenario: Home exposes one booking action
- **WHEN** a logged-in blind-runner user without an active order opens the home screen
- **THEN** exactly one booking action SHALL be present
- **AND** activating it SHALL open the slot-based booking page

## REMOVED Requirements

### Requirement: Booking uses a guided voice-first sequence
**Reason**: The owner replaced booking with "choose a date and slot, agree details on the phone" (#806, 2026-11-06).
**Migration**: The slot-based booking page in `blind-booking-match-first`.

### Requirement: Voice booking failures end on the voice stage, not the form
**Reason**: Voice booking is no longer reachable.
**Migration**: None.

### Requirement: The voice stage and the form stage are mutually exclusive
**Reason**: Neither stage is reachable any more.
**Migration**: None.

### Requirement: A failed voice path offers a booking that needs no input
**Reason**: The slot page is itself ready to submit with no input.
**Migration**: `blind-booking-match-first` default selection.

### Requirement: Voice booking always reaches an audible terminal outcome
**Reason**: Voice booking is no longer reachable.
**Migration**: None.

### Requirement: A slot snapshot never carries a value the user did not speak
**Reason**: Voice booking is no longer reachable.
**Migration**: None.

### Requirement: A half-spoken start time is echoed back so a one-word answer completes it
**Reason**: Voice booking is no longer reachable.
**Migration**: None.
