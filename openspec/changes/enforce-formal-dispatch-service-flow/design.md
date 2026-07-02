## Context

The repository is a native iOS frontend for AidRun. The backend is external, and all non-Mock traffic must continue to use the fixed cloud service at `http://47.114.113.171` and `ws://47.114.113.171`.

The current app already has phone login, role selection, blind-runner booking, volunteer dispatch summary, WebSocket dispatch prompts, order actions, polling, Mock fixtures, and TTS. The remaining release gap is that the user-facing role flows are not yet enforced as one formal lifecycle. In particular, the volunteer side can currently expose completion from `DRIVER_ARRIVED`, the blind-runner completion/rating surface is not a full first-class flow, volunteer admin review gating is not represented in the profile model, and the emergency action needs to remain a placeholder for this change instead of launching a real safety workflow.

## Goals / Non-Goals

**Goals:**

- Make the blind-runner flow complete and explicit: login, role selection, profile plus emergency contact, booking with location and 30-minute lead time, dispatch waiting, accepted/en-route/arrived tracking, in-service state, completed state, and optional rating.
- Make the volunteer flow complete and explicit: login, role selection, profile/certification/admin-review readiness, manual availability opt-in, WebSocket online state, location reporting, timed `NEW_ORDER` accept/decline, accepted order detail, en-route, arrived, wait for `IN_PROGRESS`, complete service, points, and service records.
- Enforce strict order completion: `DRIVER_ARRIVED` must not directly finish. The finish action is available only when the current order status is `IN_PROGRESS`.
- Keep business logic in ViewModels and helpers, with SwiftUI views only rendering state and forwarding actions.
- Preserve Mock as an offline frontend test facility while aligning it with the same state machine used by cloud validation.
- Add focused tests for state gating, routing, model decoding, Mock transitions, and key user flows.

**Non-Goals:**

- Do not add backend source code, database configuration, local backend scripts, or any locally runnable server.
- Do not change the fixed cloud HTTP or WebSocket origins.
- Do not add route navigation, real-time track sharing, payment, chat, administrator UI, production emergency handling, auto-call, or auto-SMS.
- Do not add a separate app administrator role.
- Do not make the old public order pool a primary volunteer flow.

## Decisions

1. **Use status-driven role routers instead of adding parallel order pages.**
   - Blind-runner navigation will route active orders by status: waiting/status tracking for `PENDING_MATCH`, `PENDING_ACCEPT`, `DRIVER_EN_ROUTE`, and `DRIVER_ARRIVED`; in-service for `IN_PROGRESS`; completion/rating for `COMPLETED`; terminal messaging for `CANCELLED` and `NO_VOLUNTEER`.
   - Volunteer navigation will route accepted active orders to detail/service views by status, but completion actions will be gated by status helpers.
   - Alternative considered: keep one generic status page for every blind-runner status. That keeps implementation smaller, but hides the expected service and completion workflows and makes rating hard to place.

2. **Centralize state-machine gates in shared helpers and ViewModels.**
   - `RunOrderStatus` helpers should define active status, poll status, cancellable status, emergency placeholder visibility, and finish-allowed status.
   - ViewModels should enforce the same gate before API calls so hidden buttons are not the only protection.
   - Alternative considered: only conditionally render buttons. That is insufficient because tests, deep links, or stale UI state could still call a forbidden action.

3. **Treat `DRIVER_ARRIVED` as a waiting state, not a finishable service state.**
   - `DRIVER_ARRIVED` will show that the volunteer has arrived and that the client is waiting for the cloud to advance the order to `IN_PROGRESS`.
   - `/api/orders/{id}/finish` must only be called from `IN_PROGRESS`.
   - Alternative considered: keep `DRIVER_ARRIVED -> COMPLETED` as a compatibility shortcut. That skips the required service-start state, breaks TTS expectations, weakens service-time accounting, and conflicts with `AGENTS.md`.

4. **Use backend status notification plus 5-second polling as the service-start bridge.**
   - The current contract has no iOS start-service endpoint. The app should receive `IN_PROGRESS` through `ORDER_STATUS_CHANGED` or polling `GET /api/orders/{id}`.
   - If the backend never advances to `IN_PROGRESS`, the UI remains in a clear arrived/waiting state and does not offer finish.
   - This creates a visible contract dependency instead of hiding it behind an invalid client transition.

5. **Decode and enforce administrator review readiness on the volunteer client.**
   - Volunteer profile models should represent `adminReviewStatus` when the backend returns it.
   - Volunteer access to the dispatch workbench and accept actions should require both certification and administrator approval when both statuses are available.
   - Alternative considered: rely on backend rejection only. Backend rejection remains necessary, but the iOS UI should not present a volunteer as ready when the contract says they are not.

6. **Keep emergency as a non-production placeholder in this change.**
   - Because the owner confirmed real emergency behavior is not launching now, the app should not imply that a real rescue workflow has completed.
   - Placeholder controls may remain visible where the product expects a future safety affordance, but the copy and behavior must be clearly non-production and must not silently call the real emergency API as if the workflow were live.
   - A later safety change can re-enable the backend `POST /api/emergency/trigger` flow with GPS, confirmation copy, TTS, volunteer response handling, compliance language, and tests.

7. **Keep old public order pool code non-primary and clearly separated.**
   - System dispatch remains the main volunteer experience.
   - Any retained `/api/orders/available` view must stay Debug/compatibility-only and must not be linked from the primary volunteer home flow.

## Risks / Trade-offs

- [Risk] The backend may not reliably advance `DRIVER_ARRIVED` to `IN_PROGRESS`. -> Mitigation: surface a waiting state, keep polling/WebSocket refresh active, and record this as a release validation dependency.
- [Risk] The backend may skip accepted travel states by returning `IN_PROGRESS` immediately after accept, or may move an accepted-but-not-started order to `REMATCHING`. -> Mitigation: keep the client rendering real backend status without synthesizing states, soften blind-runner `REMATCHING` copy, and record the behavior as a backend contract confirmation item.
- [Risk] Backend may reject `POST /api/orders/{id}/cancel` while an order is `REMATCHING`. -> Mitigation: keep the client using the existing cancel endpoint with normal error surfacing and record `REMATCHING` cancellation support as a backend confirmation item.
- [Risk] Existing tests or Mock fixtures may assume direct `DRIVER_ARRIVED -> COMPLETED`. -> Mitigation: update Mock transitions and tests to require `IN_PROGRESS` before finish.
- [Risk] Backend profile payloads may not include `adminReviewStatus` in every environment. -> Mitigation: decode the field as optional and define conservative gating rules in code and tests.
- [Risk] Emergency placeholder behavior conflicts with current docs that describe real emergency event recording. -> Mitigation: update docs in this change to mark production emergency behavior as deferred and require a future dedicated safety change before real launch.
- [Risk] Adding completion/rating UI touches blind-runner routing and TTS behavior. -> Mitigation: keep the implementation focused, use existing `CreateReviewRequest`, reuse shared `SpeechService`, and add targeted unit/UI tests around route and review submission behavior.
