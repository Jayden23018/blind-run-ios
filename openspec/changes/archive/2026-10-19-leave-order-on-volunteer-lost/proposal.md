## Why

后端 #683（#616 M6）在陪跑员点了「已出发 / 已到达」之后失联或迟迟不到时，把订单转入 `REMATCHING`，并给原陪跑员推一条 HIGH 的 `ORDER_VOLUNTEER_LOST`。这一刻起这一单已不属于他（`volunteer` 为空、详情接口回 403）。iOS #403 已让这条事件按安全提醒朗读，但陪跑员订单页仍停在已转走的单上：随后的 `ORDER_STATUS_CHANGED → REMATCHING` 让页面念一句「订单已取消，这一单不在你名下了。」，把后端的 `ttsText` 从半句切断，然后卡在「正在获取订单状态...」兜底页，不会自己离开。负责人 2026-10-17 拍板：收到后要离开这张订单页（iOS #456）。

## What Changes

- 陪跑员端收到 `ORDER_VOLUNTEER_LOST`（实时推送或重连补读；信封不带 `orderId`），且手上的订单处于 `DRIVER_EN_ROUTE` / `DRIVER_ARRIVED`：订单页离开、回到接单主页；首页的「当前订单」清掉；页面与首页都**不念**任何话，朗读只由横幅念后端 `ttsText` 一次。
- 订单页收到 `ORDER_STATUS_CHANGED → REMATCHING` 而陪跑员自己没有发起取消：页面离开，不再停在加载兜底页。
- 离开前收起页面上打开的面板（找不到对方、取消确认、上报问题、本地拨号），页面上的按钮不再对这一单发出云端请求；离开时仍在路上的流转请求，其结果不再播报。
- 不与 `ORDER_DEPARTURE_STALLED` / `REMATCHING_MID_RUN` 合并：这两条事件的处理不变。跑者端不变。

## Capabilities

### New Capabilities

（无）

### Modified Capabilities

- `volunteer-order-page`: 新增「系统把这一单转走后离开订单页」的要求。

## Impact

- `blindRun/Core/AppRealtimeCoordinator.swift`：新增不带订单号的 `ORDER_VOLUNTEER_LOST` 发布通道，实时与补读两条路都发。
- `blindRun/Volunteer/VolunteerOrderFlowViews.swift`（`VolunteerInServiceViewModel` / `VolunteerInServiceView`）、`VolunteerOrderFlowStep.swift`、`VolunteerHomeView.swift`（`VolunteerHomeViewModel`）。
- 不涉及接口契约改动；依据后端 `OrderLifecycleService.handleVolunteerLost` 与 `websocket-protocol.md` §3.2。
