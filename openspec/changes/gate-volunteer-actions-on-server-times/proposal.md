## Why

后端 #546（#307 ②）在 `OrderDetailResponse` 下发三道闸的放行时刻：`earliestDepartureAt`（确认还去 / 我出发了）、
`earliestServiceStartAt`（开始跑步）、`blindConfirmDeadlineAt`（同意闸宽限终点）。在此之前客户端只能「按了才知道」：
按钮亮着、按下去 409，而对听不见屏幕的人「按了没反应」和「按钮不在」分不出来。盲人端的「开始跑步」已在
iOS #334 接 `earliestServiceStartAt`；陪跑员端还没接（iOS issue #340）。

## What Changes

- 陪跑员订单页主按钮按后端放行时刻锁：没到时刻时原位不可按，按钮上方小字与读屏提示说「{H:mm} 起可以按」，到点后随页面每秒一拍自己亮起。
  - 「确认还去」「我出发了」「我已经出发了」读 `earliestDepartureAt`
  - 「开始跑步」读 `earliestServiceStartAt`
- 同意闸**不锁**（契约：不要置灰）：`blindConfirmDeadlineAt` 在未来时小字说「跑者还没按开始跑步。{H:mm} 起你也可以直接开始」。
- 字段缺失时不锁（由后端判，409 文案兜底）。时间闸先于同意闸的提示。

## Impact

- `blindRun/Core/Models/OrderModels.swift`（两个字段）、`blindRun/Volunteer/VolunteerOrderV2.swift`（`VolunteerActionGate`）、
  `VolunteerOrderFlowPage.swift`、`VolunteerOrderFlowViews.swift`、`VolunteerOrderFlowStep.swift`（文案）
- 契约：后端 `docs/api_spec.yaml` 的 `OrderDetailResponse`（#546）
