## Why

后端 #357（2026-09-25）起在 `NEW_ORDER` 与 `GET /api/volunteer/pending-invites` 里下发跑者的掩码姓名 `blindName`（如 `李*`）。
iOS `WSNewOrder` 没有这个字段，邀请卡与邀请态订单页的跑者行只能写「跑者」，头像圆里是「跑」；
设计稿 `volunteer-order-page-v2/02-ios-screens.md` 的读屏顺序里有「跑者李…」这一项（iOS #339）。

## What Changes

- `WSNewOrder` 接 `blindName`；`runnerName` 给出屏幕版（保留掩码）与朗读版（去星号）两份，去掉星号后为空就当没有称呼。
- 邀请卡跑者行：屏幕「跑者李*」，头像「李」，读屏「跑者李，…」。只有姓名、没有视力 / 引导方式时这一行也出现。
- 邀请态订单页：多一行「跑者 李*」（读屏「跑者李」）；绳子上跑者头像用同一个姓。
- 称呼口径按 DECISIONS-v2 V11：只用姓、不加「先生 / 女士」；整句（「跑者的全名和电话已放进订单」）仍用「跑者」。
- 更正 `VolunteerOrderFlowStep.swift` / `VolunteerInviteSheet.swift` 里「`NEW_ORDER` 没有 `blindName`」的过期注释。
- UI 测试种子带 `blindName = "李*"`，邀请卡用例断言读屏是「跑者李」。

接单前给看的判据（`AGENTS.md` §8）：掩码后只剩一个姓，不是跑者写的自由文本；契约明写它发给所有候选人。

## Impact

- `blindRun/Core/Models/DispatchInviteModels.swift`、`blindRun/Volunteer/VolunteerInviteSheet.swift`、`VolunteerOrderFlowStep.swift`、`VolunteerOrderFlowPage.swift`、`VolunteerHomeView.swift`（UI 测试种子）
- 测试：`blindRunTests/InviteRunnerNameTests.swift`、`blindRunUITests/blindRunUITests.swift`
- 契约：后端 `docs/websocket-protocol.md` NEW_ORDER 字段表 `blindName`；`api_spec.yaml` `PendingInviteItem.blindName`
