## Why

后端 #774 在 `GET /api/volunteer/dispatch-summary` 加了 `upcomingOrders`：已接单、还没出发的单（`PENDING_ACCEPT` / `SCHEDULED_CONFIRMED`），按开跑时间升序。
iOS 手写模型没有这个字段，首页每次都另打两条 `GET /api/orders/mine?role=VOLUNTEER&status=…` 取预约单（iOS #471）。
契约有两条红线：`null` 与 `[]` 意思相反；不许并进 `activeOrders`、不许注册进位置协同。

## What Changes

- `VolunteerDispatchSummaryResponse` 接 `upcomingOrders`（可选）。
- 摘要带了（非 `null`）：直接当预约列表，首页不再打那两条 `orders/mine`；每 10 秒的摘要刷新顺带刷新预约列表。
- `[]` = 确实没有，列表清空、不回落。`null`（或摘要没拉到）= 服务端没取到，回落到原来的两条 `orders/mine`。
- 只进预约列表：不进 `activeOrder`，不调 `registerActiveOrder`，不交给陪跑会话。

## Impact

- `blindRun/Core/Models/VolunteerDispatchSummaryModels.swift`、`blindRun/Volunteer/VolunteerHomeView.swift`
- `blindRun/Core/AppRealtimeCoordinator.swift`（只加一个 DEBUG 下的只读测试入口）
- 测试 `blindRunTests/VolunteerUpcomingOrdersTests.swift`
