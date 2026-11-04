## Why

The 2026-11-02 pre-launch audit (#660) found seven gaps on the blind runner's side before and after a run.
A second active booking cannot be opened, the default rating hides bad runs, and waiting, reminders,
start-place privacy and low battery are silent. The app goes public on 2026-11-09.

## What Changes

- B-5: the runner's「记录」tab lists every active booking in a new「待进行的预约」section at the top.
  Each row opens the order page, where the existing cancel entry is available.
- B-30: the rating picker has no default. Submit without a choice is refused with a spoken reason.
- B-26: the order page speaks a short status every 3 minutes while the order waits for a volunteer.
  It uses the lowest announcement tier, so it never cuts another announcement.
- B-18: when a volunteer is confirmed, the app schedules one local reminder 1 hour before the start.
  On iOS 17 and later the home page offers「加入日历」through the system editor (no calendar permission).
- F-14: when the start place is the device location, the booking form shows, and the voice readback
  says once, that the start place goes to nearby candidate volunteers and should be a public place.
- F-16: when the phone battery is at or below 20 % near the start or during the run, the app speaks
  one warning per order.
- B-13: no code change. The help page already claims Magic Tap only on the three tabs. A device check
  with VoiceOver on the order page goes into the handoff.

## Capabilities

### New Capabilities
- `blind-pre-run-support`: what the blind runner hears and can do between booking and the end of a run:
  all active bookings, waiting status, start reminder, calendar export, start-place privacy, battery, rating.

### Modified Capabilities

## Impact

- New files: `BlindRunner/BlindRunStartReminder.swift`, `BlindRunner/BlindRunCalendarExport.swift`,
  `BlindRunner/BlindPreRunCues.swift`, `BlindRunner/BlindBookingViewModel+StartPointPrivacy.swift`,
  `Shared/RunRecordUpcomingBookings.swift`, and their tests.
- Small edits: `RunExperienceRating.swift`, `BlindOrderStatusView.swift` (rating default, one modifier line),
  `BlindRunnerHomeView.swift`, `Shared/RunRecordHistoryView.swift`, `BlindBookingView.swift`,
  `VoiceOrderWizard.swift`, `Core/Services/OrderService.swift` (page size on `GET /api/orders/mine`).
- No API contract change. `GET /api/orders/mine` already returns active orders (`api_spec.yaml` `getMyOrders`).
- No new Info.plist key and no new permission prompt.
