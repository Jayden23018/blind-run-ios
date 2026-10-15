## Why

#376 之后，跑步中凭证过期时 App 进入「暂缓退出」，云端求助一律不发。跑者端的求助入口已直接切到本地拨号，
但陪跑员跑步中的求助面板（`VolunteerRunHelpPanel`）仍只有云端「长按 3 秒，紧急求助」：
按下 → 二次确认 → 协调器兜底落到「求助未发出……请直接拨打120或110」→ 陪跑员还要自己切到电话 App 拨号。
不违反 `AGENTS.md` §6，但在最需要快的时候多了几步（#381）。

## What Changes

- 陪跑员跑步中、`AppState.isSessionExpiryDeferred` 为真时，求助面板底部那枚红色按钮换成本地拨号「紧急呼叫」：
  轻点直接在面板里弹出本地拨号框（120 / 110），不经二次确认、不调 `POST /api/emergency/trigger`。
- 新增陪跑员版「登录已过期」拨号语境 `EmergencyCallContext.volunteerSessionExpired`：
  说清登录已过期、App 不会代你发送求助；不复用 `volunteerBeforeRun` 的「现在不在跑步中」，也不列紧急联系人。
- 非暂缓时面板行为一个字不变（长按 3 秒直发、轻点弹 §6 锁定文案确认框）。
- 顺带修 #438（负责人 2026-10-15 拍板并入本变更）：陪跑员跑步页的订单轮询 `VolunteerInServiceViewModel.load(orderId:speakChanges:)`
  吞掉了所有错误，401 从不交给 `handleAuthenticatedAPIError`，于是跑步中过期最常见的入口进不了暂缓，
  本变更的面板也就永远停在云端那一档。真机验收正是因此红出来的。

## Capabilities

### New Capabilities

### Modified Capabilities
- `auth-account-lifecycle`: 「暂缓期间停掉需要登录的云端操作并保留本地拨号求助」从只管跑者端扩到陪跑员跑步中求助面板。

## Impact

- 代码：`blindRun/Volunteer/VolunteerRunningCompanion.swift`（面板）、`blindRun/Safety/SafetyModule.swift`（拨号语境与文案）、
  `blindRun/Volunteer/VolunteerOrderFlowViews.swift`（宿主多传一个参数，一行）。
- 测试：`blindRunTests/SessionExpiryDeferralTests.swift`、`blindRunUITests/AccessibilityAuditTests.swift`。
- 契约：无影响。后端无改动。
