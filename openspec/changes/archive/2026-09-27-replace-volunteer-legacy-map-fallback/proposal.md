## Why

#218（PR #227）把跑步中也换成 v2 之后，陪跑员订单页上旧的「高德地图底图 + 底部面板」只剩两种情况会走到：订单详情还没拉到，以及客户端认不出的状态（`PENDING_MATCH` / `PENDING_INTRO_CALL` / `REMATCHING` / `NO_VOLUNTEER` / 未知值）。这条路上用的是系统导航栏，而系统导航栏上的求助按钮已经随 #218 删掉了。结果是这条路**违反了现行规格**（「认不出的状态也要有导航栏 + 求助入口 + 可读状态行」），还额外背着一整套只为它存在的地图与面板组件。

## What Changes

- 订单还没拉到时：v2 导航栏 + 「正在获取订单状态」加载中。
- 首次加载失败（手上没有任何订单）时：v2 导航栏 + 空状态「获取订单状态失败 / 页面会自动重试」。此前这一屏只有地图底色，一个字也没有。
- 认不出的状态：v2 导航栏 + 空状态（状态标题 + 一句说明）。不给任何流转按钮。
- 以上三种都用 v2 导航栏，右上角的求助胶囊一律走**本地拨号**（120 / 110），不走云端，因为这几种状态都不是 `IN_PROGRESS`。
- 页面不再画高德地图。**BREAKING（界面）**：删除陪跑员服务页地图底图、图例、底部面板，以及只被它们使用的组件和单测。

## Capabilities

### New Capabilities

（无）

### Modified Capabilities

- `volunteer-order-page`：「Order page switches in place by server status」补上加载中、首次加载失败两个场景，并把「认不出的状态」场景写实：求助走本地拨号，页面不给流转动作。

## Impact

- `blindRun/Volunteer/VolunteerOrderFlowViews.swift`：`VolunteerInServiceView` 的兜底分支。删除 `VolunteerServiceMapPresentation`、`VolunteerServiceMapLayout`、`VolunteerServiceMapBackdrop`、`VolunteerMapLegend`、`VolunteerServiceBottomPanel`、`VolunteerServiceStageHeader`、`VolunteerServiceRunnerCard`、`VolunteerServiceOrderEssentials`、`VolunteerServiceActions`。`VolunteerServiceActionKind` 收窄到仍被外部使用的三个 case。
- 单测：删除只测上述组件的用例，新增兜底文案的用例。
- `docs/05-page-specs.md` 页面 13：删除描述地图背景的几行。
- 不涉及接口契约，也不涉及后端。
