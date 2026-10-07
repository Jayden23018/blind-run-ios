## Why

后端 2026-09-18（迁移 0046，后端 issue #307 ①）给「开始陪跑」加了两道 409，并在盲人点头时给陪跑员推 `BLIND_START_CONFIRMED`：

- `SERVICE_START_TOO_EARLY`：距约定开跑还有超过 15 分钟，按钮该等到点。
- `BLIND_CONFIRMATION_PENDING`：盲人还没确认「可以开始」；**不是死锁**，超过约定开跑 + 15 分钟后陪跑员可单方面开始。

iOS 至今没有接：`validate-error-codes` 的未映射清单里就有这两个码，陪跑员「开始跑步」按钮亮着、一按就 409，只能念后端 message，
页面上没有「等待对方确认」这一态，`BLIND_START_CONFIRMED` 被当成一条普通通知，页面不会跟着更新。

## What Changes

- `ErrorCode` 新增 `SERVICE_START_TOO_EARLY` / `BLIND_CONFIRMATION_PENDING` 及用户文案（不写分钟数，阈值在后端配置）。
- 陪跑员汇合页：按下「开始跑步」收到 `BLIND_CONFIRMATION_PENDING` 后，按钮上方小字换成「等待对方确认」，**按钮不置灰**（对方随时可能点）。
- 收到 `BLIND_START_CONFIRMED`：清除「等待对方确认」并立刻重拉订单。该事件信封**不带 `orderId`**（`websocket-protocol.md`），
  所以只在当前订单为 `DRIVER_ARRIVED` 时生效。
- `SERVICE_START_TOO_EARLY`：只念文案，不自行计算「最早可操作时刻」（后端没有下发字段，客户端不抄阈值）。

**不做**：盲人端汇合屏的同意 / 开始按钮（后端 #346 起盲人也能直接 `start-service`，是 UI 设计决策，另开 issue）；
因此也不加 `confirm-start` 的调用方。

## Impact

- `blindRun/Core/Models/ErrorModels.swift`、`blindRun/Core/AppRealtimeCoordinator.swift`、
  `blindRun/Volunteer/VolunteerOrderFlowViews.swift`、`blindRun/Volunteer/VolunteerOrderFlowStep.swift`（及 `metUp` 构建处）。
- 契约来源：后端 `docs/api_spec.yaml` 的 `/api/orders/{id}/start-service`、`docs/websocket-protocol.md` 的 `BLIND_START_CONFIRMED`。
