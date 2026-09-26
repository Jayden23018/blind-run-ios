## Context

`VolunteerInServiceView.body` 分三路：`IN_PROGRESS` 走 `runningPage`；`VolunteerOrderPhase.resolve` 能解析的走 `flowPage`；其余走 `legacyMapContent`。第三路此前的样子是全屏地图，加上 `emergencySection` 和 `VolunteerServiceBottomPanel`。这条路上的系统导航栏在 #218 之后已经没有求助按钮了。

## Goals / Non-Goals

**Goals:**
- 第三路换成 v2 导航栏加一块纯文字状态区，满足现行规格「认不出的状态也要有求助入口」。
- 删掉只剩第三路在用的组件与对应单测。

**Non-Goals:**
- 不给这些状态设计专门的页面，也不在这里新增任何动作按钮。
- 不动 `VolunteerOrderDetailView`，它的 `VolunteerOrderMap` 小地图不属于服务页。

## Decisions

- **导航栏用 `FlowOrderNavBar`，求助固定走本地拨号**。能走到兜底路径的状态都不是 `IN_PROGRESS`（`IN_PROGRESS` 在分流里先一步被截走），订单为 nil 时 `VolunteerOrderSOSMode.resolve` 同样给出 `.localCall`。所以这里直接调 `resolve(status:)`，不自己写判据。本地拨号弹层复用 `.emergencyCallOptionsDialog(context: .volunteerBeforeRun)`，和 v2 订单页是同一个。
- **状态区用现有 `EmptyStateView`**，标题和说明取 `RunOrderStatus.serviceStageTitle / serviceStageSubtitle`，也就是旧面板头部原本念的那两句，文案不变。加载中用 `ProgressView`。
- **判断显示哪一种的那几行抽成纯函数** `VolunteerOrderFallback.resolve(status:errorMessage:)`，让单测够得着：订单为 nil 且有错误 → 失败文案；订单为 nil 且没有错误 → 加载中；其余情况 → 状态文案。
- **`VolunteerServiceActionKind` 保留，收窄到 3 个 case**。首页预约区块和跑步中页还在读 `confirmDeparture` / `releaseScheduled` / `cancelOrder` 的 `title`，搬走的话要同时改三个调用点，本次不做。

## Risks / Trade-offs

- [旧面板在这些状态下展示过跑者姓名、电话和出发地点，兜底页不再展示] → 能走到这里的状态里，陪跑员要么还不是订单参与者（`PENDING_MATCH` / `PENDING_INTRO_CALL` 下后端会回 403），要么已经不是（`REMATCHING`），本来就不该再看到这些信息。
- [UI 测试 `testRealAMapEnabledSmoke` 里断言 `volunteerServiceMapBackdrop` 不存在，而这个 identifier 从 App 里消失了] → 保留这条断言，加 `guard:allow stale-ui-test-identifier`，和同一段里 `volunteerHomeMap` 的处理方式一致。
