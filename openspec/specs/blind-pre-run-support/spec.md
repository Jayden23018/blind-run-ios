# blind-pre-run-support Specification

## Purpose
Covers what the blind runner hears and can do between booking a run and finishing it: where active bookings
are shown, the waiting status, start reminders, calendar export, start-place privacy, low battery and the run rating.
## Requirements
### Requirement: The records tab holds finished runs only
The runner「记录」tab SHALL NOT list bookings that are still active, and its load announcement SHALL NOT
count them (owner decision 2026-11-07, #823 round 2). Showing several active bookings on the home page is
tracked separately; until it ships, only the booking returned by `GET /api/orders/active` is reachable.

#### Scenario: Two active bookings
- **WHEN** the runner has one booking tomorrow and one the day after
- **THEN** neither appears in the「记录」tab and the load announcement does not mention them

### Requirement: Rating has no default
The completion rating SHALL start with no option selected. Submitting without a choice SHALL NOT call the
review API and SHALL show and speak「请先选一项：这次陪跑怎么样。没选不能提交。」.

#### Scenario: Submit without choosing
- **WHEN** the runner presses「提交评价」before choosing
- **THEN** no review request is sent and the reason is spoken

### Requirement: Waiting for a volunteer is not silent
While the order page is in the foreground and the order is `PENDING_MATCH` or `REMATCHING`, the app SHALL
speak a short waiting status every 3 minutes, at most 10 times per visit, on the lowest announcement tier.

#### Scenario: Another announcement is playing
- **WHEN** a waiting status is due while a status change is being spoken
- **THEN** the waiting status does not interrupt it

### Requirement: Start reminder after a volunteer is confirmed
When an order is `SCHEDULED_CONFIRMED` or `PENDING_ACCEPT` and its start is more than 1 hour away, the app SHALL
schedule one local notification 1 hour before the start, and SHALL remove it when the order leaves those states.
The notification SHALL NOT include the start address. The app SHALL NOT request notification permission for it.

#### Scenario: Booking cancelled after confirmation
- **WHEN** a confirmed order becomes `CANCELLED`
- **THEN** its pending reminder is removed at the next sync

### Requirement: Add to calendar without a permission prompt
On iOS 17 and later the home page SHALL offer「加入日历」for an order with a confirmed volunteer and a future start.
It SHALL use the system event editor and SHALL NOT request calendar access. On iOS 16 the button SHALL NOT appear.

#### Scenario: iOS 16
- **WHEN** the device runs iOS 16
- **THEN** no calendar button appears and no calendar permission is requested

### Requirement: Start-place privacy reminder
When the start place comes from the device location, the booking form SHALL show, and the voice readback SHALL say
once per booking,「出发地点会发给附近的候选陪跑员，建议约在公共地点，不要约在家门口。」.

#### Scenario: Searched start place
- **WHEN** the runner picked a searched place as the start
- **THEN** the reminder is not shown or spoken

### Requirement: Low battery warning
When the battery level is known, at or below 20 %, not charging, and the order is underway or starts within 2 hours,
the app SHALL speak one warning per order that names the level.

#### Scenario: Phone is charging
- **WHEN** the level is 15 % and the phone is charging
- **THEN** no warning is spoken


### Requirement: The home page shows every active booking
The blind home page SHALL show every order whose status is active for the blind runner, earliest planned start first
(#825, owner decision 2026-11-07). The booking from `GET /api/orders/active` SHALL be first; the others come from
`GET /api/orders/mine`. With one booking the card is unchanged. With two or three, the cards SHALL share the height
of the single card equally, and SHALL grow when their content does not fit. Each card SHALL be one VoiceOver element
whose label starts with the planned time, and SHALL open that order's page. The load announcement SHALL say how many
bookings there are when there is more than one. When the other bookings fail to load, the page SHALL say so on screen
and in the announcement, and offer a retry.

#### Scenario: Three active bookings
- **WHEN** the runner has bookings on 8, 12 and 15 November
- **THEN** the home page shows three cards in that order, each about a third of the single card's height,
  and the announcement starts with「你有 3 张预约。最近一张：」
