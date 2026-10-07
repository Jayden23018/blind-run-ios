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
- 后端 #546（#307 ②）下发 `earliestServiceStartAt`：没到点时「开始跑步」原位不可按，副标题与读屏提示说「9:45 起可以开始跑步」，
  到点后随 5 秒轮询亮起。字段缺失时不锁，按下由后端判。
- 409 `SERVICE_START_TOO_EARLY`（字段缺失时才会走到）：只念文案，不拿 `plannedStartTime` 自己减。
  `ORDER_STATUS_NOT_ALLOWED`：本地状态已过期，刷新订单而不是重试。
- 汇合态的状态说明与到达播报去掉「请等待志愿者开始服务」，改为说清见面后按「开始跑步」出发；订单页副标题用设计稿原文「见面后，轻点下方开始跑步」。
  首页与语音状态查询不在订单页上，不说「轻点下方」。
- 按下后请求在途期间（含重拉订单），主按钮原位变成不可点的「准备中」并先播一句「正在开始跑步。」——
  慢网络下按钮外观不变、再按被静默吞掉，对盲人端就是「点了没反应」。
- 打电话给陪跑员不再占主按钮，仍可从「遇到问题」进入的求助与安全中心拨出（设计稿每屏只有一个主按钮）。
- 「请等待志愿者开始服务」原是两端共用的一句（`arrivedWaitingCopy`）：陪跑员误点结束时也听到「请等待志愿者」。
  拆开：盲人端用新的到达句，陪跑员结束守卫用自己的一句。陪跑员页的状态播报整张表仍借用盲人端文案，
  这是独立问题（另开 issue 修），所以新的到达句写成对两端都为真。
- 错误码文案：`SERVICE_START_TOO_EARLY` 改说「开始跑步」（按钮名）；`BLIND_CONFIRMATION_PENDING` 说出跑者那一端的按钮名。
- Mock：订单已是 `IN_PROGRESS` 时 `start-service` 返回成功（契约：「另一端先按了 → 两端都返回 200」）。
- **不做**：单独的 `confirm-start`「我准备好了」按钮 —— 盲人端只有一个主按钮位，「开始跑步」已包含同意；
  只点头不开跑会让盲人按完还要等陪跑员再按一次。

## Impact

- `blindRun/BlindRunner/BlindOrderFlowStep.swift`、`blindRun/BlindRunner/BlindOrderStatusView.swift`
- `blindRun/BlindRunner/BlindOrderFlowView.swift`（读屏提示）
- `blindRun/Core/Models/OrderDisplayHelpers.swift`、`OrderModels.swift`、`ErrorModels.swift`、`blindRun/Voice/SpeechService.swift`（文案）
- `docs/02-mvp-scope.md`、`docs/05-page-specs.md`、`docs/09-accessibility-and-voice-guidelines.md`、`docs/testflight/test-information.md`
- `blindRun/Core/MockAPIClient+IntroCall.swift`
- 契约：后端 `docs/api_spec.yaml` 的 `/api/orders/{id}/start-service`（#346）与 `/confirm-start`
