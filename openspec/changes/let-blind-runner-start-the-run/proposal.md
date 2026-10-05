## Why

后端 #307（迁移 0046）给「开始陪跑」加了同意闸：陪跑员调 `start-service` 前，盲人必须先同意；否则陪跑员收到 409 `BLIND_CONFIRMATION_PENDING`，
要等到约定开跑时间过 15 分钟才能单方面开始，而那一次不写 `blindStartConfirmedAt`。后端 #346 随后放开盲人 token 调 `start-service`：
**盲人按下 = 同意 + 开始**，先按的生效。

iOS 盲人端至今两个都没接（`confirm-start` 与盲人 `start-service` 调用方都是 0）。陪跑员侧在 #318 接好了「等待对方确认」，
但盲人那一侧没有任何入口能让对方等到这个确认 —— 于是每一单都只能等满 15 分钟宽限再强制开始。

设计稿五处一致要求盲人汇合屏的主按钮是「开始跑步」（`docs/ui/mockups/running-state/状态清单.md` §1：
「见面后，轻点下方开始跑步」；`volunteer-home-accept-v3` §5：「双方都能按，先按的生效」）。
盲人端此前用「打电话给张伟」顶替，理由是「后端不让盲人调 `/start-service`」—— 那个理由自 #346 起不成立。

## What Changes

- 盲人汇合态（`DRIVER_ARRIVED`）的主按钮改为「开始跑步」，调 `POST /api/orders/{id}/start-service`。成功后订单进 `IN_PROGRESS`，
  沿用既有的三秒倒计时（它挂在状态转移上，不挂在谁按了按钮上）。
- 409 `SERVICE_START_TOO_EARLY`：只念文案，不在客户端计算最早可开始时刻（后端没下发字段，见后端 #307 ②）。
  `ORDER_STATUS_NOT_ALLOWED`：本地状态已过期，刷新订单而不是重试。
- 汇合态的状态说明与到达播报去掉「请等待志愿者开始服务」，改为说清两人都能开始；订单页副标题用设计稿原文「见面后，轻点下方开始跑步」。
  首页与语音状态查询不在订单页上，不说「轻点下方」。
- 打电话给陪跑员不再占主按钮，仍可从「遇到问题」进入的求助与安全中心拨出（设计稿每屏只有一个主按钮）。
- Mock：订单已是 `IN_PROGRESS` 时 `start-service` 返回成功（契约：「另一端先按了 → 两端都返回 200」）。
- **不做**：单独的 `confirm-start`「我准备好了」按钮 —— 盲人端只有一个主按钮位，「开始跑步」已包含同意；
  只点头不开跑会让盲人按完还要等陪跑员再按一次。

## Impact

- `blindRun/BlindRunner/BlindOrderFlowStep.swift`、`blindRun/BlindRunner/BlindOrderStatusView.swift`
- `blindRun/Core/Models/OrderDisplayHelpers.swift`、`blindRun/Voice/SpeechService.swift`（汇合态文案）
- `blindRun/Core/MockAPIClient+IntroCall.swift`
- 契约：后端 `docs/api_spec.yaml` 的 `/api/orders/{id}/start-service`（#346）与 `/confirm-start`
