## Why

**后端的播报文案已经在教用户点一个 App 里不存在的按钮。**

订单长时间无人接单时，后端推 `ORDER_CANCELLATION_WARNING`（HIGH 优先级），文案逐字是：

> 您的订单即将因长时间无人接单被取消，**点击继续等待可延长**

iOS 侧对 `PUT /api/orders/{id}/keep-waiting` 与 `PUT /api/orders/{id}/keep-rematching`
**零命中**（全仓搜索）。于是这条 HIGH 优先级播报走通用分支被念出来，
盲人听到「点击继续等待」，屏幕上没有这个按钮，而他看不见屏幕——
**能做的只有等着订单被自动取消，然后重新下一单。**

前端自己知道少了这块，证据在 `blindRun/Core/Models/ErrorModels.swift:20`：
`KEEP_WAITING_LIMIT_REACHED` 已经映射了，而这个错误码**只有调那两个端点才可能收到**。
映射了一个永远收不到的码。

## What Changes

- 盲人订单状态页在 `PENDING_MATCH` / `REMATCHING` 两态提供「继续等待」主动作，
  调用对应端点刷新超时窗口。
- 收到 `ORDER_CANCELLATION_WARNING` 时把该动作提到显著位置并播报出路。
- 达到延长上限（409 `KEEP_WAITING_LIMIT_REACHED`）时如实告知并收起入口。
- **不改 `NO_VOLUNTEER` 的终态定性**（见下）。

## 一条必须先纠正的认识

本变更的上游 review 报告（`docs/frontend-backend-alignment-review-20260812.md` §A4）
写的是「`.noVolunteer` 在 15 处被当终态与 `.cancelled`/`.completed` 同组，**要拆开**」。
**那句是错的，本变更不照它做。**

核实（后端 `origin/main`，已 `git fetch`）：

- `OrderStatus.java:46` —— `NO_VOLUNTEER; // 超时无人接单（预留终态）`
- `DispatchService.java:574` —— 「`NO_VOLUNTEER` 是终态」
- `OrderStatus.java:86` —— `PENDING_MATCH, REMATCHING, NO_VOLUNTEER, COMPLETED, CANCELLED -> false`

**前端把 `NO_VOLUNTEER` 当终态是对的**，两个端点的前置状态也**不是**它：
`keep-waiting` 用于 `PENDING_MATCH`，`keep-rematching` 用于 `REMATCHING`
（后者契约里写死了「其他状态返回 409 `ORDER_STATUS_NOT_ALLOWED`」）。

真正的缺口比报告写的更窄、也更要紧：**可恢复的窗口在订单走到 `NO_VOLUNTEER` 之前**。
等它变成 `NO_VOLUNTEER` 就已经晚了——那时确实没有出路，而这正是要避免的结局。

## 与其它未归档变更的关系（归档顺序有约束）

本变更 MODIFY 的 `formal-dispatch-service-flow` 里的
**Requirement: Blind runner state updates remain status driven**，
`enable-live-escort-location-and-track-summary` 也 MODIFY 过同一条。

- 本变更的 MODIFIED 块**已基于 live-escort 那一版写**（含它加的
  `Volunteer location is available` / `REST fallback is used before service` 两个 Scenario）。
- 因此**本变更必须在 `enable-live-escort-location-and-track-summary` 之后归档**，
  否则会把它那批 Scenario 覆盖回去。
- 与 `enable-independent-sos-safely` 无冲突：它改的是
  **Requirement: Cancellation visibility is role-aware**，本变更不碰那一条
  （「继续等待」是新增动作，不改任何状态的取消可见性）。

## 需要后端确认的

1. **`keep-waiting` 在契约里没有 description**（`api_spec.yaml:235-254` 只有 operationId 和 200）。
   它的前置状态、角色、上限只能靠 `keep-rematching` 的描述对称推断。请补齐，
   我们不想把「靠对称猜出来的语义」写进客户端分支。
2. **`NO_VOLUNTEER_AVAILABLE` 通知与 `NO_VOLUNTEER` 状态同名但不同义**：
   通知文案是「您的订单**仍在等待中**」，而状态是终态。
   我们的 `AppRealtimeCoordinator.lifecycleStatus` 目前把该 eventType 映射成 `.noVolunteer`
   （用于播报去重）。请确认：收到该通知时订单状态**仍是** `PENDING_MATCH`/`REMATCHING`，
   而不是已经落到 `NO_VOLUNTEER`。
3. 延长成功后是否有 WebSocket 事件回告？还是只有 200？
   没有的话客户端只能靠自己的乐观更新 + 5 秒轮询，届时读屏用户听到的确认来自本地文案。
