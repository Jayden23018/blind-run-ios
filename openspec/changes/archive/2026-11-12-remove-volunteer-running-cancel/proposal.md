## Why

负责人 2026-11-12 批准陪跑员订单页 v7 补齐稿（#962，`docs/ui/mockups/volunteer-order-v7-parity-20261112/DECISION.md` 第 3 条）时追加：跑步中页「取消陪跑」按钮不要，追问后选「整个删掉」（不是收进「···」）。跑步中要离开，走右上角求助面板或长按结束。

同一批补齐里，跑步中地图一直不画路线（非完成态 `route` 恒为空），而盲人端 v7 ⑦ 画的是 `/track` 实时轨迹。

## What Changes

- **BREAKING（入口删除）**：陪跑员 `IN_PROGRESS` 页底部只留「长按 2 秒，结束陪跑」，删掉灰色「取消订单」按钮（identifier `volunteerRunningCancel`）。
- 删掉跑步中那套取消确认文案 `VolunteerOrderFlowCopy.runningCancelSheet`（#653）和只为它服务的单测；`cancelSheet(for:)` 不再有 `IN_PROGRESS` 分支。
- 取消弹层开着时订单进入 `IN_PROGRESS`：弹层收起（跑步中没有取消入口，不留一个按下去已不成立的面板）。
- 跑步中地图画跑者实时轨迹：取页面已在拉的同一次 `GET /api/orders/{id}/track` 的 `primaryRouteCoordinates`。
- 其他状态的取消（约好页「我去不了」、出发 / 汇合页「···」里的取消）不动。后端仍允许志愿者在 `IN_PROGRESS` 取消，本变更只删客户端入口，不动契约。

## Capabilities

### New Capabilities

（无）

### Modified Capabilities

- `volunteer-running-page`：删掉「跑步中保留取消入口」；「跑步中使用 v7 地图页」加上画实时轨迹。

## Impact

- 代码：`blindRun/Volunteer/VolunteerRunningPage.swift`、`VolunteerInServiceView+Flow.swift`、`VolunteerInServiceView.swift`、`VolunteerCancelSheet.swift`、`VolunteerOrderFlowStep.swift`、`VolunteerInServiceViewModel.swift`。
- 测试：`AlertAnnouncementPriorityTests` 删跑步中取消文案那条；UI 用例 `blindRunUITests+VolunteerService.swift` 横屏那条不再断言取消按钮，改断言它不存在。
- 契约：无。
