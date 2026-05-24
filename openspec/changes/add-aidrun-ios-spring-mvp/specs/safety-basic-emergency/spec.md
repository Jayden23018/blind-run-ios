## ADDED Requirements

### Requirement: Emergency contact is mandatory for blind runners

The system MUST require emergency contact name and phone in the blind runner profile before booking.

#### Scenario: Missing emergency contact
- **WHEN** a blind runner tries to book without emergency contact data
- **THEN** the backend returns `PROFILE_INCOMPLETE`

### Requirement: Emergency action requires confirmation

The iOS app MUST show a confirmation dialog before entering emergency state.

#### Scenario: User taps emergency
- **WHEN** a user taps one-tap emergency
- **THEN** the app shows “是否确认进入求助状态？确认后，本次服务将标记为异常，系统会记录当前订单状态。”

### Requirement: Emergency is available only during active service preparation or service

The system MUST allow emergency transition only from `accepted`, `arrived`, or `in_progress`.

#### Scenario: Emergency from accepted order
- **WHEN** a user confirms emergency for an `accepted` order
- **THEN** the order status becomes `emergency` and an emergency event records the previous status

### Requirement: Emergency state is not restored in MVP

The system MUST not support restoring an order from `emergency` back to its previous state.

#### Scenario: Emergency already entered
- **WHEN** an order is in `emergency`
- **THEN** normal lifecycle actions such as arrive, confirm-start, complete, or cancel are rejected

### Requirement: MVP records safety data without real notifications

The MVP MUST store emergency contact and emergency event data without auto-calling, sending SMS, or notifying a real administrator.

#### Scenario: Emergency triggered
- **WHEN** an emergency event is created
- **THEN** the backend records the event and performs no automatic phone call or SMS
