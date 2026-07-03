## Design

The service-start transition is a volunteer-owned order action, not a new order status. The iOS client keeps the canonical statuses unchanged and adds one action endpoint between arrival and completion:

`DRIVER_ARRIVED -> POST /api/orders/{id}/start-service -> IN_PROGRESS -> POST /api/orders/{id}/finish -> COMPLETED`

Blind-runner screens remain passive for this transition. They keep showing status tracking while the order is `DRIVER_ARRIVED`, then move to the in-service experience when WebSocket or polling returns `IN_PROGRESS`.

The volunteer UI exposes a 64pt "开始服务" action only for `DRIVER_ARRIVED`; "结束服务" remains visible and executable only for `IN_PROGRESS`. Mock and cloud E2E follow the same path so tests do not rely on the old debug-only `/mock-start-service` route or a direct `DRIVER_ARRIVED -> finish` attempt.
