## Why

后端 #445（PR #563，负责人 2026-10-06 同意）把 `POST /api/orders/{id}/ring-runner` 放开到 `IN_PROGRESS`：陪跑中走散时，陪跑员可以让跑者的手机响。跑者端收到的是新的 `eventType=RUNNER_RING_LOST`（「你的陪跑员在找你，请原地停下」），信封与汇合期的 `RUNNER_RING` 相同。

iOS 现状（后端 issue #565）：盲人端只认 `RUNNER_RING`，`RUNNER_RING_LOST` 落到普通横幅，只念一次、不循环、不放提示音，而陪跑员那边接口返回 200、`delivered=true` —— 两边都以为响了。陪跑员端跑步中求助面板也没有响铃入口（DECISIONS-v2 V5 / V12 当时因为后端不允许而删掉）。

## What Changes

- 跑者端收到 `RUNNER_RING_LOST`：与 `RUNNER_RING` 同一套响铃（先念、循环提示音到 `until`、任意操作即停、重复投递不重响、缺 `until` 时回落为普通通知念一次），遮罩与兜底朗读改用走散文案，标题是「请原地停下」。两句话不混用。
- 陪跑员端跑步中求助面板在「暂停」之后加一行「让{名}的手机响起来」：按下收起面板并调 `ring-runner`；`ringingUntil` 之前这一行显示「正在响铃…」且不可点。
- 跑步页显示响铃回执（没送到 / 按得太频繁），且回执在订单状态变化时清掉，汇合期那句不会带进跑步中。
- 设计决定源 `DECISIONS-v2.md` V5 / V12 记录推翻来源。走散提示条仍不带响铃按钮（V7 不变）。

## Capabilities

### New Capabilities

### Modified Capabilities
- `running-rhythm-and-help`: 跑步中求助面板多一行响铃；新增跑者端接收走散响铃。

## Impact

- 代码：`blindRun/BlindRunner/RunnerRing.swift`（`RunnerRingRequest.Kind`、按种类取文案）、`BlindRunnerTabView`（遮罩传种类、UI 测试接缝支持 `lost`）、`AppRealtimeCoordinator` 路由、`VolunteerRunningCompanion.swift`（面板一行与文案）、`VolunteerOrderFlowViews.swift`（面板接线、跑步页回执、状态变化清回执）。
- 契约：只读后端 `api_spec.yaml` `ring-runner` 与 `websocket-protocol.md` `RUNNER_RING_LOST` 一行，不改。
- 部署顺序：后端迁移 `202610061338` 先于新 JAR，缺它时接口 200 但 `delivered=false`，iOS 走「对方可能没收到」那一支。
