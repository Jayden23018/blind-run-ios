## Why

后端 #682（blind-run-backend PR #701，2026-10-10 合并）放开了一条出口：陪跑员标了「已到达」之后，跑者满一段时间（默认 10 分钟，起点是「这一次到达」与「计划开跑」中较晚的那个）可以取消订单。只有跑者知道陪跑员到底在不在现场；没有这条出口，「陪跑员标了到达、一直在线、人却不来」时跑者只能干等到计划结束 + 60 分钟被自动完成。iOS 主线还没接：手写模型没有 `earliestBlindCancelAt`，汇合页也没有取消入口（iOS #395，后端问题单 #696）。

## What Changes

- 订单详情解码 `earliestBlindCancelAt`；缺键、`null`、类型不对都不连累整张订单。
- 跑者订单页汇合态（`DRIVER_ARRIVED`）加「取消本单」一行（负责人 2026-10-17 拍板的交互）：
  - `earliestBlindCancelAt` 为 `null`：不出现（后端关了这条出口）。
  - 还没到那个时刻：置灰不可按，读屏念「X 点之后可以取消，先给陪跑员打电话」。
  - 到点之后：可按，走既有二次确认，调 `POST /api/orders/{id}/cancel`。
  - 页面开着跨过那个时刻：自动变可按，并播报一次。
- 取消失败的朗读：409 `BLIND_CANCEL_TOO_EARLY` 念后端 `message`（含可取消时刻）；409 `ORDER_HAS_ACTIVE_EMERGENCY` 在跑者取消这一路给跑者口径的文案。`ErrorCode` 加 `BLIND_CANCEL_TOO_EARLY`。
- 陪跑员端：`ORDER_CANCELLED_BY_BLIND_AFTER_ARRIVAL` 永不被「订单页自己会播」那道闸吞掉；陪跑中页面从汇合态进入跑者取消时，念的那句加上「你可以离开集合点了」。
- `AGENTS.md` §5：盲人可取消状态加 `DRIVER_ARRIVED`（带后端时间门槛），`DRIVER_EN_ROUTE` / `IN_PROGRESS` 仍不可取消。

## Capabilities

### New Capabilities

（无）

### Modified Capabilities

- `blind-order-page`：汇合态新增带时间门槛的取消入口及其朗读。
- `volunteer-order-page`：跑者在到达后取消时，陪跑员要听得到「可以离开了」。

## Impact

- 代码：`blindRun/Core/Models/OrderModels.swift`、`ErrorModels.swift`、`APIClient.swift`（`localizedMessage` 对少数码优先用后端 message）、`blindRun/BlindRunner/BlindOrderFlowStep.swift` / `BlindOrderFlowView.swift` / `BlindOrderStatusView.swift`、`blindRun/Volunteer/VolunteerOrderFlowViews.swift` / `VolunteerOrderFlowStep.swift`、`blindRun/Core/AppRealtimeCoordinator.swift`（只加注释与用例钉住「不映射」）、Mock。
- API：只读契约既有字段与错误码，不改契约。
- 文档：`AGENTS.md` §5。
