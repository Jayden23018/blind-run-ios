## Context

All seven items live on the blind runner side. `BlindOrderStatusView.swift` is frozen and at its SwiftLint
file-length baseline, so new logic goes into new files and the frozen file only gets one modifier line plus the
rating default. Another session edits the running page and the safety hub at the same time.

## Goals / Non-Goals

**Goals:** close B-5, B-18, B-26, B-30, F-14, F-16 on iOS only, with no contract change; record B-13 for a device check.

**Non-Goals:** volunteer battery reporting (F-16 second half), street-level address before acceptance (F-14
backend half), Magic Tap handler on the order page (B-13/B-21 belong together), reminders while the app never runs.

## Decisions

- **B-5 data source.** `GET /api/orders/mine` returns all orders newest first, 10 per page by default. A runner
  can hold at most 3 active orders, and an active order is at most about 7 days old. The service now asks for
  50 per page so the active ones are always on the first page. Alternative: a backend `status in` filter. Not needed.
- **B-26 tier.** `.perKilometer` is the lowest tier: it never interrupts, and it is dropped after 10 s in the queue.
  A periodic "still waiting" line has the same nature. `.onDemand` was rejected: it would cut「重复当前状态」.
  Interval 3 minutes: long enough not to nag, short enough that a first-time user hears the system is alive
  before they start to doubt it (audit scenario: 20 minutes of silence).
- **B-18 sync.** The reminder set is rebuilt from `GET /api/orders/mine` whenever the home page's active order
  changes. Rebuild (remove ours, add wanted) avoids keeping per-order state. Lead time 1 hour.
- **B-18 calendar.** Apple docs (Accessing the event store; TN3152, checked 2026-11-04): on iOS 17+ EventKitUI runs
  out of process and needs no access. On iOS 16 it needs full access and two Info.plist keys. We hide the button
  on iOS 16 instead of adding a permission prompt.
- **F-16 tier.** `.onDemand`: below status changes, above per-kilometre lines. Dedupe per order id in memory.
- **B-30.** `reviewRating` becomes optional. The submit button stays enabled so a VoiceOver user who presses it
  hears why; a disabled button says nothing.

## Risks / Trade-offs

- Reminders are only scheduled when the app runs after confirmation. Background push stays the main channel.
- The calendar event does not follow later cancellations. The event notes say so.
- Timing of spoken lines can only be checked by ear on a device.
