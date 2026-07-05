## Why

Recent dual-device validation found inconsistent order-state copy, unstable volunteer map markers, ambiguous blind-side distance wording, unsafe direct playback of backend notification templates, and unclear role-specific cancellation affordances. These issues affect launch readiness because blind runners rely on clear TTS and predictable state guidance, while volunteers need stable service-map context.

## What Changes

- Display `PENDING_ACCEPT` as "待出发" on both blind-runner and volunteer surfaces.
- Use order-detail-driven local TTS for lifecycle states; backend `APP_NOTIFICATION` templates are not spoken directly for lifecycle updates.
- Announce volunteer acceptance with appointment time and start address, and treat volunteer departure as a later status update.
- Calculate blind-runner distance copy from the latest volunteer WebSocket location to the order start coordinate, using "距出发地点约 X".
- Keep the volunteer service map centered on the order start coordinate and update AMap annotations by stable id without repeated drop animation.
- Make cancellation role-aware: blind runners can cancel `PENDING_MATCH`, `PENDING_ACCEPT`, and `REMATCHING`; volunteers can cancel `PENDING_ACCEPT`, `DRIVER_EN_ROUTE`, `DRIVER_ARRIVED`, and `IN_PROGRESS`.
- Auto-search the start-place field when speech recognition finishes with recognized text, and expose listening/search/result states through VoiceOver announcements.
- Hide raw latitude/longitude text from normal blind-runner and volunteer UI while preserving coordinates in models, API requests, and map annotations.
- After cancellation attempts, keep UI state aligned with the real backend response and avoid stale volunteer service screens when the volunteer token is no longer an order participant.
- Do not add backend implementation or change HTTP/WebSocket contracts.

## Impact

- iOS UI/ViewModels: blind booking search, blind order status, blind home status replay, volunteer service actions, and AMap bridge.
- Shared models/helpers: order display copy, role-aware cancellation helpers, local TTS copy, and distance formatting.
- Documentation: user stories, state machine, page specs, and accessibility/voice guidelines.
- Tests: unit coverage for status copy, role-aware cancellation, distance source, lifecycle notification suppression, volunteer service actions, and map presentation anchoring.
