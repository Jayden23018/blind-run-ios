## Context

The backend already exposes the required order statuses and transition endpoints. The iOS client only needs to normalize how those states are presented and acted on. The key product decision is that `PENDING_ACCEPT` means a volunteer has accepted the dispatch and the next user-facing step is preparing to meet at the appointment start point; it is not a blind-runner confirmation state.

## Decisions

- Keep `PENDING_ACCEPT` as the backend status, but present it as "待出发".
- Generate blind-runner lifecycle TTS from local order details so the app can include start time and start address and avoid backend test-template names.
- Continue speaking safety-specific WebSocket events, but suppress direct speech for lifecycle-like `APP_NOTIFICATION` text while an active order is present.
- Use latest `VOLUNTEER_LOCATION_UPDATE` coordinates and `order.startLatitude/startLongitude` for blind-side distance copy. Do not show distance when either side is missing.
- Keep the volunteer service map anchored on the order start coordinate. The volunteer current location may be shown as an auxiliary marker, but it must not move the map center.
- Make cancellation visibility role-aware in the iOS client, while continuing to use `POST /api/orders/{id}/cancel`.
- Treat start-place speech input as a field-level dictation helper: when recognition ends with non-empty text, trigger the same AMap POI search as the search button; do not parse appointment time from speech.
- Mirror important TTS prompts to VoiceOver announcements so VoiceOver users hear repeat-status, search-state, and result-summary feedback even when AVSpeech is not the active accessibility channel.
- Use the system AMap user-location layer for volunteer current location on service maps; keep custom annotations limited to the order start marker to avoid marker jump/drop during location updates.
- Do not perform a volunteer-side detail fetch after successful cancellation because the backend may remove the volunteer from the order. Clear the local volunteer active-order state instead; blind-runner polling remains the source of truth for `REMATCHING` or `CANCELLED`.
- Align cancel affordances with the backend contract: blind runners may cancel only `PENDING_MATCH`, `PENDING_ACCEPT`, and `REMATCHING`; volunteers may cancel active non-terminal accepted service states `PENDING_ACCEPT`, `DRIVER_EN_ROUTE`, `DRIVER_ARRIVED`, and `IN_PROGRESS`, and successful volunteer cancellation moves the order to `REMATCHING`.

## Non-goals

- No backend source code, local backend, database changes, or new API endpoints.
- No route planning or in-app navigation engine.
- No production emergency event integration beyond existing placeholder behavior.
- No change to the canonical order status values.
- No visible raw coordinate readout in normal user-facing booking or dispatch views.
