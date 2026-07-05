## 1. Specs And Docs

- [x] 1.1 Add OpenSpec change for order copy, TTS, distance, map stability, and role-aware cancellation.
- [x] 1.2 Update user stories, state-machine, page specs, and voice/accessibility docs.
- [x] 1.3 Add follow-up acceptance details for speech search, VoiceOver result feedback, hidden coordinate readouts, and cancellation state convergence.

## 2. iOS Behavior

- [x] 2.1 Change `PENDING_ACCEPT` display and blind-runner copy to "待出发" / accepted-volunteer guidance.
- [x] 2.2 Add order-detail-driven blind-runner TTS with appointment time and start address.
- [x] 2.3 Handle `VOLUNTEER_LOCATION_UPDATE` in blind order status and display distance to the start point.
- [x] 2.4 Suppress direct speech of lifecycle-like backend `APP_NOTIFICATION` text.
- [x] 2.5 Add role-aware cancellation helpers and update blind/volunteer UI visibility.
- [x] 2.6 Anchor volunteer service map at start coordinate and sync AMap annotations by stable id.
- [x] 2.7 Auto-search start-place speech input and announce listening/search/result states through VoiceOver.
- [x] 2.8 Remove raw coordinate text from normal booking and volunteer dispatch UI.
- [x] 2.9 Keep volunteer service map custom annotations fixed on the order start marker and cleanly exit after volunteer cancellation.

## 3. Tests And Validation

- [x] 3.1 Add or update unit tests for status copy, TTS, distance source, lifecycle notification suppression, role-aware cancellation, service actions, and map presentation.
- [x] 3.2 Run docs validation, OpenSpec validation, and iOS test commands.
- [x] 3.3 Add follow-up unit coverage for speech-search completion, VoiceOver announcement helpers, no-coordinate display text, fixed marker presentation, and cancellation cleanup.
- [x] 3.4 Align blind/volunteer cancellation permissions and mock `REMATCHING` behavior with the backend contract.
