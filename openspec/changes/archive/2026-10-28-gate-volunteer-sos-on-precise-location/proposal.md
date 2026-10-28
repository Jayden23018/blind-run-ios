## Why

陪跑员在跑步中代跑者按云端求助时，坐标直接取 `LocationService.latestBackendSample()`，不看陪跑员自己手机的「精确位置」开关。
开关关着时那是约 5 公里外的区域代表点，照样当求助坐标发出去 —— 违反 `AGENTS.md` §6「云端 SOS 必须带新鲜的真实 GCJ-02 坐标，拿不到就不发」。
`gate-blind-location-on-precise-accuracy` 当时把这一处列为有意不改（其 design.md 的 Non-Goals），
security-reviewer 复核后开了 Jayden23018/blind-run-ios#407；2026-10-28 协调会话代项目负责人定为「拦截」（#407 第 1 项）。

## What Changes

- 陪跑员两处云端求助入口（确认框、跑步中求助面板）改走跑者端同一道闸 `EmergencyCoordinator.freshEmergencyCoordinate`：
  新鲜、真实、精确位置开着、本角色同意过共享位置，四条缺一条就不发。
- 精确位置关着时先用已有的 `LocationService.requestTemporaryPreciseLocation(for: .escortVolunteer)` 申请一次临时精确位置，
  最多等 15 秒（`EmergencyCoordinator.preciseLocationAnswerTimeout`）；允许了就带坐标发出。
- 仍关着（或没同意共享位置、拿不到定位）：不发云端求助，播报并在页面上写出原因（「求助未发出：…精确位置已关闭…请直接拨打120或110」），
  并自动弹出本地拨号兜底（新语境 `EmergencyCallContext.volunteerCloudUnsent`，只列 120 / 110，说清 App 不会代你发送求助）。
- 判定「确定一个字节都没发」集中在 `EmergencySOSState.isDefinitelyUnsent`，只有 `unsentNoLocation` / `unsentSessionExpired` 两态成立。

## Impact

- 代码：`blindRun/Safety/EmergencyCoordinator+Location.swift`、`EmergencySOSState.swift`、`EmergencyCallContext.swift`、
  `blindRun/Volunteer/VolunteerOrderFlowViews.swift`（两处求助入口与 `enterEmergency` 返回值）。
- 不改契约、不改后端；不改跑者端行为（跑者端仍不在求助时弹系统窗，理由见 `freshEmergencyCoordinate` 注释）。
- #407 的第 2 项（陪跑中同行位置上报）与第 3 项（语音下单消歧）不在本变更内。
