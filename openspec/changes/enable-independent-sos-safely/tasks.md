## 1. Safety Preconditions And Contract Confirmation

- [ ] 1.1 Complete and validate `complete-realtime-fallback-and-notifications` and `enable-live-escort-location-and-track-summary` before implementing SOS UI.
- [ ] 1.2 Obtain product/safety approval for strict current-GPS gating versus backend location degradation and for pending/failure/retry/resolved copy.
- [ ] 1.3 Confirm structured trigger response/errors/cooldown, both-role authorization, contact-notified semantics/delivery to both participants, resolved states, and reconnect/relaunch recovery; mark every gap `需要人工确认`.
- [ ] 1.4 Keep both release-facing entries disabled until tasks 1.2 and 1.3 are resolved.

## 2. Canonical Documentation And Contracts

- [ ] 2.1 Update `AGENTS.md` to replace the hidden-emergency rule with the approved dual-role `IN_PROGRESS`-only flow while preserving the exact confirmation copy.
- [ ] 2.2 Update `plan.md` and product/scope/story/flow/page/data/architecture/accessibility/task docs with eligibility, GPS, event/SMS states, failure behavior, responsibility boundaries, and release risk.
- [ ] 2.3 Update `docs/07-api-contract.openapi.yaml` with required iOS order/GPS usage, structured trigger result/errors, both-role authorization, event recovery, and unchanged order status.
- [ ] 2.4 Update `docs/websocket-protocol.md` with event-ID/order-ID-keyed submitted/contact-notified/resolved messages for both participants and exact SMS semantics.

## 3. Models And Mock Safety State

- [ ] 3.1 Add typed dual-role request, structured trigger response, emergency event status, error/cooldown, contact-notified/resolved, and recovery models.
- [ ] 3.2 Reuse the live escort GCJ-02 value type and forbid demo/fallback coordinates for cloud SOS requests.
- [ ] 3.3 Implement Mock `IN_PROGRESS` blind/volunteer triggers, GPS/order validation, pending, failure, contact notification, resolution, cooldown, recovery, and no order-state mutation.

## 4. Emergency Coordination

- [ ] 4.1 Implement an event-ID-keyed `EmergencyCoordinator` integrated with `AppRealtimeCoordinator`, with no ownership of `RunOrderStatus`.
- [ ] 4.2 Revalidate authenticated participant role and canonical `IN_PROGRESS` order immediately before sending.
- [ ] 4.3 Obtain a fresh real GCJ-02 location from the active escort session or bounded one-shot request; implement the approved no-location behavior and never use demo coordinates.
- [ ] 4.4 Gate submitted state on structured success, protect against duplicate taps, and keep network/decoding/backend rejection visibly and audibly unsent.
- [ ] 4.5 Route contact-notified/resolved updates only when event ID, order ID, authenticated participant, and documented role delivery match.
- [ ] 4.6 Persist only approved non-secret recovery metadata scoped to authenticated user/order and clear it on logout, deletion, expiration, user change, terminal event, or disassociation.

## 5. Dual-Role IN_PROGRESS Experience

- [ ] 5.1 Show a 64pt+ SOS action on blind and volunteer service screens only while canonical status is `IN_PROGRESS`; hide it in every other state.
- [ ] 5.2 Use the exact required second-confirmation copy, send no request on cancel, and disable duplicate confirmation while submitting.
- [ ] 5.3 Present equivalent visible, VoiceOver, and TTS states for locating, submitting, processing, unsent/failure, cooldown, contact-notified, and resolved outcomes.
- [ ] 5.4 Show/speak “联系人已收到短信” only after the approved matching backend notification; never derive it from HTTP trigger success.
- [ ] 5.5 Include authoritative SOS state in blind repeat-current-status without replacing canonical order status or changing finish/cancel permissions.

## 6. Tests And Validation

- [ ] 6.1 Add unit tests for role/order eligibility, exact confirmation, cancel/no-request, current-GPS encoding, structured success gating, duplicate/cooldown, event matching, recovery isolation, and unchanged order status.
- [ ] 6.2 Add tests for no/stale location, permission revocation, background/lock triggering, network/decoding failures, and prohibition of demo coordinates.
- [ ] 6.3 Add blind/volunteer UI/accessibility tests for state visibility, 64pt targets, exact copy, TTS/VoiceOver equivalence, and SMS copy appearing only after matching notification.
- [ ] 6.4 Extend cloud probes for both-role `IN_PROGRESS` trigger, GCJ-02/order payload, notification semantics, recovery, and no order-status mutation.
- [ ] 6.5 Run `node scripts/validate-docs.mjs` and `openspec validate enable-independent-sos-safely --strict --no-interactive`.
- [ ] 6.6 Run focused tests and supervised locked/background dual-device safety acceptance on `111` and `iPad Pro (2)` before release enablement.
