## Why

后端 #361（PR #541）给 `POST /api/orders/{id}/cancel` 加了响应体 `CancelOrderResponse { success, countedAsLateCancel }`：
陪跑员距开跑不足 `app.order.late-cancel-window-hours`（默认 12 小时）取消时记一次「临时取消」，只记不罚。
契约要求「**以这个字段为准**才能对陪跑员说『已记一次』」。iOS 现在不解码这个响应体，陪跑员取消后不知道这件事。

同时后端 #356（PR #540）新增 `GET /api/config/rules`，下发两个原先被 iOS 写死的数：
- `lateCancelWindowHours` —— 客户端写死在 `VolunteerOrderFlowCopy.lateCancelWindowHours = 12`，决定取消弹层要不要多一句提醒；
- `volunteerOrderAutoOpenLeadMinutes` —— 客户端写死在 `AppConstants.Timing.volunteerOrderAutoOpenLeadMinutes = 120`。
两处注释都写着「后端给出配置就改读配置」。不改的话后端调参，客户端的提醒与跳转仍按旧数走。

另外取消弹层里「会记一次临时取消」这半句当初被删，理由是「后端零实现」。那个理由不再成立。

## What Changes

- 解码取消接口的 `CancelOrderResponse`。陪跑员三条取消路径（订单页、跑步中页、首页「我去不了」）在 `countedAsLateCancel == true` 时，
  在取消成功那一句后面加「已记一次临时取消。」；`false` 或缺字段时不说。不提任何后果（契约：只记不罚）。
- WebSocket 的状态推送常比取消响应先到。先念了取消那一句、后拿到 `true` 时，追加那一句排在后面播，不切断前一句。
- 陪跑员订单页 / 跑步中页转 `REMATCHING` 时只念一句。原来先念盲人端的状态句、再被同档的取消句切断。
- 接 `GET /api/config/rules`（需登录、不限角色）。取消弹层的窗口小时数与自动打开订单页的提前量改读它；拿不到或值不合法时退回当前的 12 小时 / 120 分钟。
- 取消弹层在窗口内的那一段恢复「现在取消会记一次临时取消」，仍不写任何后果。是否真的记了以取消响应为准。
- Mock：`/api/config/rules` 返回契约默认值；陪跑员取消按窗口算 `countedAsLateCancel`，盲人取消恒为 `false`。

## Impact

- `blindRun/Core/Models/`（`RuleParamsModels.swift` 新增、`OrderModels.swift`）、`blindRun/Core/Services/AuthService.swift`、`OrderService.swift`、`AppState.swift`、`EnvironmentConfig.swift`
- `blindRun/Volunteer/VolunteerOrderFlowViews.swift`、`VolunteerOrderFlowStep.swift`、`VolunteerCancelSheet.swift`、`VolunteerHomeView.swift`
- `blindRun/Core/MockAPIClient*.swift`；`scripts/openapi/openapi-generator-config.yaml`（漂移探测器加 `/api/config/rules`）
- 契约：后端 `docs/api_spec.yaml` 的 `/api/orders/{id}/cancel`（`CancelOrderResponse`）与 `/api/config/rules`（`RuleParamsResponse`）
