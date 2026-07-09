## Context

The iOS client currently contains volunteer screens and documentation centered on nearby order browsing (`GET /api/orders/available`) and manual volunteer selection. Product direction and backend implementation have moved to backend-controlled dispatch: volunteers opt in with the availability switch, connect `/ws/volunteer`, report location, and receive `NEW_ORDER` prompts from the backend.

The blind-runner side still creates appointments and follows the same order state machine. Its waiting state needs to describe backend system dispatch rather than public volunteer browsing. The repository remains an iOS-only frontend; the backend is external and real network traffic continues to use `http://47.114.113.171` and `ws://47.114.113.171`.

## Goals / Non-Goals

**Goals:**
- Align docs, OpenSpec, API contract notes, and UI handoff docs with backend-controlled dispatch.
- Replace volunteer home primary content with a dispatch workbench driven by `GET /api/volunteer/dispatch-summary`.
- Preserve the availability switch as the volunteer's explicit opt-in to receive dispatches.
- Keep `NEW_ORDER` handling as a 30-second accept/decline prompt using `POST /api/orders/{id}/respond`.
- Update blind-runner matching copy, TTS, and status replay text to say the system is dispatching volunteers.
- Add mock and tests for dispatch summary parsing, temporary points display, readiness reasons, and updated blind-runner waiting copy.

**Non-Goals:**
- Do not implement backend matching, ranking, expansion rings, or dispatch algorithms in the iOS repository.
- Do not add a public order pool fallback or "later" dispatch business action.
- Do not implement a real points ledger, points shop, payment, route navigation, real-time track sharing, or backend admin tools.
- Do not change the canonical order statuses or add emergency as an order status.

## Decisions

1. **Use `dispatch-summary` as the volunteer home source of truth.**
   - The volunteer home page will load `GET /api/volunteer/dispatch-summary` for readiness, reasons, coverage, stats, active orders, and recent orders.
   - Alternative considered: continue combining `/api/volunteer/profile`, `/api/orders/available`, and `/api/orders/mine`. That keeps stale public-pool behavior and makes readiness explanations inconsistent with backend dispatch.

2. **Keep `GET /api/orders/available` out of the primary volunteer experience.**
   - The public list and "view all orders" entry points will be removed or downgraded from the home page. Existing detail/service screens remain for accepted/current orders.
   - Alternative considered: show available orders as a secondary fallback. This contradicts the confirmed product decision and reintroduces volunteer self-selection.

3. **Model dispatch summary separately from `OrderDetailResponse`.**
   - Backend summary fields use `plannedStartTime` / `plannedEndTime`, while existing order detail uses `plannedStart` / `plannedEnd`. Separate models avoid destabilizing booking/detail flows.
   - Alternative considered: make `OrderDetailResponse` decode every variant. That hides contract differences and increases risk in existing order pages.

4. **Temporary points are derived on the client until a real points API exists.**
   - If `pointsBalance` is not available, display `totalCompleted * 100`. If `recentOrders.pointsDelta` is missing, display `+100` for completed orders and `0`/dash otherwise.
   - This is a placeholder only; no points ledger or shop behavior is introduced.

5. **Blind-runner waiting remains status-driven.**
   - The blind runner does not see internal dispatch rounds. UI updates come from `ORDER_STATUS_CHANGED`, `APP_NOTIFICATION`, and 5-second `GET /api/orders/{id}` fallback.
   - This keeps the blind-runner surface stable while backend dispatch logic evolves.

6. **`NEW_ORDER` coordinates are optional but supported.**
   - The client will decode `startLatitude` and `startLongitude` if present. The dispatch prompt can still render a text-only state when coordinates are missing.

## Risks / Trade-offs

- [Risk] Backend `dispatch-summary` fields may arrive incrementally or omit temporary stats. → Mitigation: make non-critical stats optional and display clear placeholders.
- [Risk] Existing docs still contain nearby order-list language after implementation. → Mitigation: update the top-level product, flow, page, architecture, API, WebSocket, and UI handoff docs in the same change.
- [Risk] Removing public-pool entry points can leave old views unreachable but still compiled. → Mitigation: keep service/detail views for current orders and tests, but remove them from the primary home navigation.
- [Risk] Mock behavior may drift from the backend. → Mitigation: mirror the backend-provided response shape and keep real integration validation as release sign-off.
- [Risk] Blind-runner users may not understand a long `PENDING_MATCH` wait. → Mitigation: use explicit system-dispatch copy, TTS replay, and backend notifications for "still searching" and `NO_VOLUNTEER`.
