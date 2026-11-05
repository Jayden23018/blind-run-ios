## Why

「约定结束时间 + 超时提醒」（功能清单第 6 条）在开工时被当成待建功能。查现状发现**两半都不是**：

**结束时间这一半：契约里一直有，前端一次都没显示过。** `OrderDetailResponse.plannedEnd`
是 `api_spec.yaml` 里的 required 字段，iOS 模型里也有（`OrderModels.swift:317`），
但全仓搜下来它只出现在模型定义、`MockAPIClient` 的种子数据和下单请求的构造里 ——
**没有任何一个视图渲染它**。盲人和志愿者都看不到、听不到这次跑步约定几点结束。

**超时提醒这一半：后端当天已经修好并上线，不是待建。** `ORDER_OVERDUE` 的模板和 `ttsText`
一直在后端库里，但它在生产上**一次都没被触发过** —— 两个定时器互相抵消：
`OrderTimeoutScheduler` 每 60 秒把过了 `plannedEndTime` 的订单直接置成 `COMPLETED`，
而发告警的任务要求订单在超时 1 小时后**仍是** `IN_PROGRESS`，订单最多活 60 秒就被收走。
后端 N63（`918bf01`，#85）已修：`plannedEnd + 15min` 发告警、`+60min` 才自动完成。

后端在 handoff 里点名问了两件事，这个变更同时回答它们。

## What Changes

- **约定结束时间可见也可听**：
  - 盲人端订单状态页 —— 服务进行中摆在首屏状态卡里（低视力用户看得到），
    并进「重复当前状态」的主播报（读屏用户听得到）；「预约信息」折叠区里加一行。
  - 志愿者端服务卡与订单信息卡各加一行。
  - 一律取 `plannedEnd`，**不许**用 `plannedStart + expectedDurationMinutes` 推。
- **`ORDER_OVERDUE` 在客户端提为高优先级**：抢占前台播报队列、红色横幅、`isHeader` trait。
  实时推送与断线补读走同一条规则。
- **不做本地通知**。见「非目标」。

## 非目标（明确不做，不是漏做）

- **不排本地通知（`UNUserNotificationCenter`）当超时兜底。** 后端已经在 `plannedEnd + 15min`
  推 `ORDER_OVERDUE`，客户端再排一条只会：时间与服务端不一致、订单提前结束时要记得撤销、
  且两条一起响。盲人端收不到推送的真正原因在后端（见下），不是缺一条本地通知 ——
  拿本地通知去补，等于用一个时间不对的提醒盖住一个真正的缺口。
- **不按 `plannedEnd` 在本地推断订单已结束。** 后端明确警告过这条：自动完成的时间点从
  `+0min` 推后到了 `+60min`，任何「过了 `plannedEndTime` 就本地当作已结束」的推断
  现在会和服务端差一小时。**核过全仓：这样的代码一处都没有**（`plannedEnd` 从未与当前时间
  比较过），这条是确认不是修复。
- **不改后端模板优先级**。那是后端的东西，已投 handoff。

## 需要后端确认的

1. 🔴 **盲人端 `ORDER_OVERDUE` 模板是 `NORMAL`（`websocket-protocol.md:158`），而 APNs 只补发
   `HIGH`（`NotificationService.java:134`）—— App 不在前台时盲人根本收不到超时告警。**
   志愿者侧同一个 eventType 是 `HIGH`（`:451`），收得到。
   也就是说「跑者可能失联」这件事，唯一收不到通知的是跑者本人。
   客户端抬优先级只影响前台横幅与播报顺序，**改不了推送能不能到达**——判据是模板值。
   请把盲人侧模板提到 `HIGH`。
2. 志愿者侧 `ORDER_OVERDUE` 的文案还写着「订单已超过结束时间**1小时**」
   （`websocket-protocol.md:451`），N63 之后实际是 **15 分钟**。文案和行为对不上。
3. 盲人侧文案「您的陪跑订单已超时，志愿者会尽快结束服务」假定志愿者在场且会处理，
   而 N63 的复盘逐字写着这条告警的语义是「跑者**可能失联**」——
   失联时这句话会让盲人以为一切正常、只是慢了点。

## 回后端的两个问题（handoff 2026-08-13 点名要答）

1. **「这两端的 `ORDER_OVERDUE` 你们现在收到了会怎么表现？」**
   走通用 `APP_NOTIFICATION` 通道：`AppRealtimeCoordinator.routeNotification` → 前台横幅
   + `ContentView` 里 `speechService.speak(notification.speechText)`。
   它**没有**被 `shouldSuppressLifecycleNotification` 吞掉（`lifecycleStatus` 对它返回 nil，
   因为它不宣布任何订单状态）—— 这一点本变更加了回归用例钉住。
   本变更把它在客户端提为 `HIGH`，于是它抢占播报队列、红色横幅、带 header trait。
   **但 App 不在前台时它根本到不了**，原因见上面第 1 条。
2. **「有没有按 `plannedEndTime` 本地推断订单已结束的代码？」**
   **没有。** 全仓 `plannedEnd` 只出现在模型、Mock 种子数据、下单请求构造，
   一处都没有与当前时间比较。位置上报、WS 订阅、进行中卡片的收起全部以服务端 `status` 为准。
