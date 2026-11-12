## Context

跑步中页 `VolunteerRunningPage` 底部原有两样：长按结束 `VolunteerFinishLongPressButton` 和灰字「取消订单」（`onCancel` → 宿主 `activeSheet = .cancelOrder` → `VolunteerCancelSheet`，文案走 `cancelSheet(for: .inProgress)` → `runningCancelSheet`）。取消弹层另外还从出发 / 汇合页「···」和约好页「我去不了」打开，这些不动。

## Goals / Non-Goals

**Goals:** 跑步中没有任何取消入口；跑步中专用文案和它的用例一起删；跑步中地图画实时轨迹。

**Non-Goals:** 不改契约（后端仍允许志愿者 `IN_PROGRESS` 取消）；不改求助面板；不把取消挪进「···」。

## Decisions

1. **删参数，不留可选闭包。** `VolunteerRunningPage.onCancel` 整个删掉，调用点编译期就够不着，不会有人传一个闭包把按钮带回来。
2. **`cancelSheet(for:)` 不再特判 `.inProgress`。** 那条分支只为跑步中入口服务；入口没了，留着就是死代码。
3. **取消弹层在进入 `IN_PROGRESS` 时收起。** 汇合页打开弹层、跑者那边同时按了开始：此前弹层会换成跑步中文案；现在跑步中不该有取消，所以收起，同 `.runHelp` 离开 `IN_PROGRESS` 时收起的写法。
4. **轨迹复用已有请求。** view model 的 `refreshBlindStatsIfNeeded` 已每 10 秒拉一次 `/track`，同一个响应里取 `primaryRouteCoordinates` 存成 `liveRunRoute`，不新增请求；离开 `IN_PROGRESS` 时清空，失败不清（与盲人端 `refreshTrackStatsIfNeeded` 同理）。

## Risks / Trade-offs

- 跑到一半陪跑员真的陪不了（受伤），客户端没有「转给别人」的出口，只能求助面板联系客服或长按结束（结束会记成完成）。这是负责人知情下的取舍：跑步中让跑者被留在路上的风险更大。
