## Why

#407 第 2 项定为「拦截」后（#534），精确位置关着时这一端不上报同行位置。两端横幅说「走散提醒用不了」，这不对。
后端在 `IN_PROGRESS` 读不到一方坐标时走 `EscortSafetyService.checkSignalMissing`：先给双方发 `ESCORT_SIGNAL_LOST`，
缺失满 `app.escort.signal-missing-grace-seconds`（默认 180 秒）仍没有，就按 `AI_DETECTED` 建紧急事件、走求助升级流程。
用户需要在开跑前知道：一直关着，几分钟后系统会按失联处理。

## What Changes

- 两端「精确位置已关闭」横幅改写：去掉「走散提醒用不了」，说清开始跑步后一直关着的话，几分钟后系统会按失联处理、自动启动求助流程。
- 时长只说「几分钟后」，不写具体秒数：那是后端配置项，后端改了值客户端不知道。
- 只说将来会发生什么，不说「已发出」「已通知」，也不提短信（AGENTS.md §6）。
- 进入 `IN_PROGRESS` 时精确位置仍关着：横幅换成跑步中的那一句，并再朗读一次（开跑时的提醒）。
- 更正 `2026-10-28-gate-escort-sharing-on-precise-accuracy/design.md` 里「走散提醒不工作」的风险说法。

不做：让后端对「精确位置关闭」只提醒不升级（方案 C）。那会削弱防止有人关定位躲开走散监控的那道防护。

## Capabilities

### Modified Capabilities

- `escort-precise-location-gate`：告知的文案要求改写；新增「进入跑步时再提醒一次」。

## Impact

- `blindRun/Core/LiveEscortSessionCoordinator.swift`：`LiveEscortHealthState.preciseLocationOff` 带上 `running`。
- `blindRun/Core/EscortPreciseLocationCopy.swift`（新）：两端、跑步前后共四句文案。
- 测试：`EscortPreciseLocationGateTests`、新 `EscortPreciseLocationEscalationTests`。
- 不改后端契约。
