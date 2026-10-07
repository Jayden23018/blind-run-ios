# Tasks

- [x] 1.1 `BlindOrderFlowPresentation.PrimaryAction` 加 `.startRun`；`DRIVER_ARRIVED` 主按钮取它（先于打电话）。
- [x] 1.2 `BlindOrderStatusViewModel.startRun()`：调 `orders.startService`，成功后重拉订单；409 `SERVICE_START_TOO_EARLY` 念文案不置位、`ORDER_STATUS_NOT_ALLOWED` 刷新。
- [x] 1.3 汇合态文案：订单页副标题用「见面后，轻点下方开始跑步」；通用描述与播报不再说「请等待志愿者开始服务」，也不说「轻点下方」。陪跑员误点结束时的那句拆出来单独写。
- [x] 1.4 Mock：`start-service` 在 `IN_PROGRESS` 时返回成功（契约：另一端先按也是 200）。
- [x] 1.6 请求在途时主按钮原位变「准备中」并先播一句；错误文案在重拉之后设（审查 A5 / B1 / B2）。
- [x] 1.7 接 `earliestServiceStartAt`（后端 #546）：没到点时按钮原位不可按并说出钟点；字段缺失不锁。
- [x] 1.5 删掉过期注释（「盲人 token 调不了 `/start-service`」）；`docs/02` `05` `09` 与 TestFlight 说明同步。
- [x] 2.1 单测：主按钮、副标题、通用文案、VM 成功 / 太早 / 已开始三条路径；验红。
- [x] 2.2 改掉钉住旧行为的 `testMetUpDoesNotOfferStartServiceBecauseOnlyTheVolunteerCanCallIt`，`BlindRunPhaseTests` 里「已知缺口」注释随之收口。
- [x] 2.3 `openspec validate --all --strict`；真机跑覆盖的 suite 与 UI 用例 `testBlindRunnerCanStartTheRunFromTheArrivalScreen`。

> 2026-10-06：2.1 验红已做 —— 实现为空壳时真机 iPhone 16 Pro 跑 `BlindStartRunTests`：`passed=2 failed=9`，
> 9 条都红在「还没实现」上。实现后 `build-for-testing` 已 TEST BUILD SUCCEEDED、`openspec validate --all --strict` 42 passed；
> **但改完之后的真机测试还没跑**（iPhone 自动锁屏后变成 `unavailable`），所以 2.1 / 2.3 不勾，PR 保持草稿。
>
> 2026-10-06 新鲜上下文审查：A 档 5 条已修（旧用例断言旧文案、到达句被陪跑员端念到时不成立、两条主规格漏改、
> 文档误写两端都倒计时、请求在途无反馈）。根因更深的「陪跑员页状态播报借用盲人端文案表」另开 iOS #333。
>
> 2026-10-07 真机 iPhone 16 Pro（免费个人团队签名）：清单 7 个 suite 首轮 `passed=412 failed=2`，
> 两条红都是本变更漏改的旧用例（`BlindOrderFlowPresentationTests` 里钉着「汇合态主按钮是打电话」「汇合态副标题以通用说明开头」）——
> 实现按设计如此，改用例：拨号闸改在仍给「打电话」的出发态测，汇合态副标题由 `BlindStartRunTests.testMetUpSubtitlePointsToTheButtonBelow` 管。
> 改后重跑 `BlindOrderFlowPresentationTests` + UI `testBlindRunnerCanStartTheRunFromTheArrivalScreen`：`passed=19 failed=0`。
> `BlindStartRunTests` 17 条逐条核过为 passed。
