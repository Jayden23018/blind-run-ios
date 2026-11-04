## Context

- 规则参数已有：`AppState.ruleParamsResponse` + `loadRuleParamsIfNeeded()`，只拉一次，登出不清 —— 对按账号下发的 `launchScope` 不够。
- 盲人下单只有一个入口：`BlindRunnerHomeView.booking(startsWithVoice:startPlace:)`，外面已经套了 `BlindBookingTrackConsentGate`。
- `BlindBookingView.swift`、`VoiceOrderWizard.swift`、`AppState.swift` 在 SwiftLint baseline 里，只许变短；`ErrorModels.swift` 不在 baseline，上限 400 行。
- 不认识的 errorCode 已经念后端 `message`，所以三个码现在「念得出来」，缺的是落位与「暂未开放」的出口。

## Goals / Non-Goals

**Goals:** 填表前告知；三个码原样播报并回到该改的一步；见面安排单错误落位。

**Non-Goals:** 不在客户端拦截提交；不改语音 `/parse` 流程；不改首页卡片；不缓存跨账号。

## Decisions

1. **闸门放在首页入口，包住整个下单页**（新 `BlindBookingLaunchScopeGate`），而不是在 `BlindBookingView.body` 里加分支。
   包在外面时，暂未开放根本不实例化下单页，语音向导的 `onAppear` 自动启动无从发生；改冻结文件的 `body` 则要加行。
   第一次进入且本账号还没有规则数据时，先显示「正在确认」再决定；拉失败就放行（后端兜底）。已有数据时立即放行，后台重读。
2. **`ORDER_SERVICE_NOT_OPEN` 由 AppState 记下「后端刚说暂未开放」**（把本地 `launchScope` 改成 `acceptingOrders = false`、提示句用后端 message），
   闸门据此换成告知页并念这句。备选是下单页自己显示一块告知 —— 要改冻结文件、且仍留着一张填不了的表。
   下单页这一侧不念，避免告知页出现时的播报把它切断。下次进入入口时强制重读会用真实数据覆盖。
3. **两步提示用纯函数**：`LaunchScopeResponse.contains(latitude:longitude:)`（四边都含）与 `admits(start:calendar:)`
   （北京时间、按分钟、两端都含、不认识的星期名忽略）。下单页只多两行渲染调用，文案拼接在 `BlindBookingViewModel+LaunchScope.swift`。
4. **提交逻辑搬进 `BlindBookingViewModel+Submit.swift`**：要改的正是它，搬走后冻结文件净变短，给两行提示腾出余量。
5. **错误码**：三个码进 `prefersServerMessage`；本地兜底句（后端 message 为空时）放 `LaunchScopeCopy`，`ErrorModels.swift` 只加枚举值与一行委托，保持 ≤ 400 行。

## Risks / Trade-offs

- [告知页在下单页提交后才出现，表单被丢弃] → 暂未开放时没有可改的项，契约也要求回首页，可以接受。
- [首次进入多一次网络往返] → 只在本账号还没有规则数据时等待；失败立即放行。
- [矩形只是近似，边界附近会误提示] → 只提示不阻断，以后端返回为准，契约原话。
