## Why

上线前真实使用审计（2026-11-02）在跑步中这一段找到三处盲人自己没有出路的地方（#660 的 B-4 / F-10、F-20，#682）：

- 陪跑员手机没电或掉线时，后端已允许盲人在陪跑员超过 5 分钟没上报位置后调 `POST /api/orders/{id}/finish` 结束（契约 finish 端点说明，后端 #346）。
  iOS 盲人端没有入口，单子只能卡到计划结束后 60 分钟自动完成。`ORDER_OVERDUE` 的盲人模板还叫他「让志愿者点击结束服务」，而此刻陪跑员可能根本联系不上。
- 陪跑员身体不适或倒地时，两台手机在一起，走散告警不会触发。求助中心有 120 和「播报我的位置」，但没有一句话告诉盲人按什么顺序用。
- #657 只在「使用帮助」里教了 iPhone 自带的紧急 SOS。手机放进臂包后，这是唯一不用碰屏幕的求助路径，开跑那一刻没有再提醒一次。

## What Changes

- 跑步中（`IN_PROGRESS`）的求助中心加一个按钮「陪跑员联系不上，结束本次陪跑」。按下先弹二次确认，确认后调 `finish`。
  - 成功：订单进入 `COMPLETED`，完成那一句改成「你已结束本次陪跑」，不说「某某结束了本次陪跑」。
  - 409 `VOLUNTEER_STILL_ONLINE`：原样显示并朗读后端 `message`（带最早可结束的时刻）；`message` 为空时用本地兜底句。
  - 其他错误照 `APIError.localizedMessage` 念。客户端不自己判陪跑员是否掉线。
- 跑步中的求助中心加一段固定指引「陪跑员身体不适或倒地怎么办」：先拨 120，再用「播报我的位置」，然后联系紧急联系人。不做摔倒检测。
- 盲人端收到 `ORDER_OVERDUE` 时，横幅与播报换成本地文案：一切正常请陪跑员结束；联系不上时可以在求助与安全里自己结束；遇到危险按求助。陪跑员端照念后端原文。
- 开跑倒计时走完、播完「开始跑步」之后，排队念一次系统紧急 SOS 的提醒（同时按住侧边按钮和任一音量按钮）。文案说明这是 iPhone 系统功能，App 不会代为求助。
- 删除 `BlindOrderFlowStep.swift` 里「盲人 token 必然 403」那句过期注释（F-28）。

**不做**：摔倒检测；开跑前的提醒不做成视觉卡片；求助中心其他格子的顺序和集合不变；云端求助的判定与逐字锁定的确认文案不变。

## Capabilities

### New Capabilities
- `blind-run-safety-hub-exits`: 跑步中盲人在陪跑员失联或出事时的出路，以及开跑时系统紧急 SOS 的提醒。

### Modified Capabilities

## Impact

- 新文件：`blindRun/BlindRunner/BlindRunnerFinish.swift`（文案、结束动作、完成句的选择）、`blindRun/Safety/SafetyHubRunSection.swift`（求助中心里的指引与按钮）。
- 冻结文件只改等行数：`SafetyHubView.swift`、`BlindOrderStatusView.swift`（求助中心调用点、开跑倒计时、完成句调用点）、`BlindOrderFlowStep.swift`（注释）、`AppRealtimeCoordinator.swift`（`overriddenBody` 一行）。
- `SafetyModule.swift` 的求助中心挂载函数加一个可选参数。
- 后端不改。`ORDER_OVERDUE` 后台推送（APNs）仍是后端模板原文，记进 PR 交接。
