## Why

Stages 2–3 of the post-run record plan (`~/Downloads/run-record-handoff/DECISIONS.md`) delivered the typed record (`RunRecordServing.record(orderId:)`, capability `post-run-record`) and the records tab, but a volunteer who opens a finished run still lands on the old order page and the `/track` replay (`OrderRouteReplayView`): one blue line, three numbers, no pace, splits, rests, or timeline. Stage 4 (HANDOFF §6.2, P0 part) gives volunteers the real post-run detail and, per D13, replaces `OrderRouteReplayView` for them.

## What Changes

- New volunteer post-run detail page fed by `RunRecordServing.record(orderId:)`: map on top (route with a near-black outline under a pace-coloured line, kilometre markers, start/end merged when they coincide, rest markers, fitted above the card), and a card with avatars, "和X一起跑", date and place, big distance, 3+3 stats, the volunteer-service row, a Swift Charts pace chart with `AXChartDescriptor`, a split list (tapping a row highlights that kilometre on the map), the in-run timeline ending with the SOS line from `sosTriggered`, and existing messages read-only.
- **Outline colour deviates from HANDOFF (project owner, 2026-09-24)**: near-black `#1C1C1E` instead of white in both appearances, because the D8 pace colours on white are 2.61:1 (mid) and 1.88:1 (slow). D8 values unchanged.
- States per HANDOFF §6.4: loading, `GENERATING` (copy + automatic re-read every 2 s), `INSUFFICIENT_TRACK` / no `track` (map hidden, "这次没有记录到完整路线"), `FAILED` and network errors with "重试", unknown status, missing step data (columns and sentences hidden, never 0).
- No confirmation status anywhere (D5). Pace written `6'15"` on screen, "每公里6分15秒" for VoiceOver. The map is one accessibility element with a route description; its markers are not exposed. Stats stack vertically at accessibility text sizes.
- Entry points: the volunteer records-tab row and the "查看大图路线" link inside `CompletedTrackSummaryView` on the three volunteer order pages now open the new page. The blind runner's link keeps `OrderRouteReplayView` until stage 5.
- `AMapContainer` gains route styles (outline, pace gradient via `MAMultiPolyline` + `MAMultiColoredPolylineRenderer`, highlight) and drawn markers (kilometre, start/end, rest, split bubble), and a configurable fit padding.
- Mock `handleGetRunRecord` returns a ~3 km loop with pace samples, splits, a rest stop and the full event list.

Not in this change (P1 or later stages): track replay, night style, chart scrubbing and chart–map linkage, map parallax / nav-bar morph, message composer (stage 6), runner detail (stage 5).

## Capabilities

### New Capabilities

- `volunteer-run-record-detail`: What the volunteer post-run detail shows, how every state is presented, and its accessibility contract.

### Modified Capabilities

- `live-escort-location-and-track-summary`: "Completed summary uses the blind track as the run route" — the volunteer's full-screen route view becomes the new detail page.
  ⚠️ That capability is still an unarchived delta in `enable-live-escort-location-and-track-summary` (task 6.6 open). **This change must be archived after that one** (project owner, 2026-09-24).

## Impact

- iOS UI: new `Volunteer/VolunteerRunRecordView.swift`, new `Shared/RunRecordPresentation.swift`; `Shared/CompletedTrackSummaryView.swift`, `Shared/RunRecordHistoryView.swift`, three call sites in `Volunteer/VolunteerOrderFlowViews.swift`; `Map/AMapContainer.swift`.
- Mock: `Core/MockAPIClient+RunRecord.swift`.
- Backend contract: consumed as-is (`getRunRecord`, `RunRecordResponse`). No contract change.
- `postMessage` stays uncalled until stage 6.
