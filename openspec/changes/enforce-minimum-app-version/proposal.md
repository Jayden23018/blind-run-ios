## Why

全仓没有版本检查。2026-11-09 受控公开之后，第一批用户拿到的版本如果不带这个检查，以后就没有办法要求他们升级（#526）。
后端接口已合入（`GET /api/config/app-version`，blind-run-backend#913），但还没部署，线上对这个路径返回 401。
所以客户端必须把一切失败当成「不拦」：这个接口出问题时，不能把所有人挡在 App 外面。

## What Changes

- 启动、登录状态变化、回到前台（`scenePhase == .active`）时读一次版本要求。
- 当前版本低于 `iosMinSupportedVersion`：全屏提示必须更新，只有「去更新」「紧急呼叫」「重复当前状态」三个动作。
- 当前版本低于 `iosLatestVersion`：弹可关闭的提示，关闭后同一个版本不再提示。
- 字段缺失、请求失败（含线上现在的 401 和 429）、版本号解析不了、更新地址不是 https：一律不提示、不拦截。
- 有进行中的订单或未结束的求助，或者判断不了有没有时：不盖全屏，也不弹提示。下一次启动或回到前台再判。

**不做**：不缓存上一次的结果（缓存会让一次错配置在断网时继续拦人）；不在订单结束的那一刻立刻弹（回到前台时再判）；
不改任何求助判定，强制更新页只用现有的本地拨号弹窗，**绝不调 `/api/emergency/trigger`**。

## 取舍

**为什么任何未走完的订单都让路，而不只是跑步中。** 求助判定（`BlindHomeSOSMode.resolve` / `VolunteerOrderSOSMode.resolve`）
只区分 `IN_PROGRESS` 和其余状态，而「不能盖掉当前订单」比求助的范围大：陪跑员的 `SCHEDULED_CONFIRMED` 有 60 分钟临期确认，
`PENDING_INTRO_CALL` 有 20 分钟通话窗口，跑者的 `DRIVER_ARRIVED` 要和人汇合。这些都是全屏页盖不得的。
「什么算未走完」不自己定义：跑者用服务端 `GET /api/orders/active` 与 `isActiveForBlindRunner`，
陪跑员用 `dispatch-summary` 的 `activeOrders` / `introCallOrderId` / `upcomingOrders`。

**代价**：手里有预约单的人，要到这一单走完才会被拦。旧版本与后端已经不兼容时，这段时间他们用的是旧版本。
这是负责人定的优先级：不能盖掉求助和当前订单。

**请求排在隐私同意之前。** 这个请求不带任何用户信息、不需要登录，与同意页上的 `legal-links` 同一性质。
强制更新要拦住还没同意的旧版本用户，所以全屏页排在同意门之上；可关闭的提示要等同意之后才弹。

**已知限制。** ① 全屏页是根视图 overlay，用户正开着 sheet 或 fullScreenCover 时要等它关闭才看得到。
② 全屏页期间陪跑员的接单开关不变，收到的派单看不到（已开 issue 跟进）。
③ 没有资料的陪跑员查订单得到 404，算「查不清」，不会被拦：现有错误类型分不出这种 404 和别的 404，判错会盖住正在跑步的人。
④ 全屏页显示期间每半秒重写一次读屏隐藏，因为背后的容器可能后挂载，也可能被邀请卡写回。

## Impact

- Affected specs: 新增 `app-version-gate`
- Affected code: `blindRun/ContentView.swift`、`blindRun/Core/Services/AuthService.swift`、
  `blindRun/Core/AppStatePersistence.swift`、`blindRun/Core/MockAPIClient+AuthenticatedReads.swift`、
  `blindRun/Safety/EmergencyCallContext.swift`、`blindRun/Shared/HostedContainersAccessibilityHider.swift`，
  新增 `blindRun/Core/AppUpdatePolicy.swift`、`blindRun/Core/AppUpdateGate.swift`、`blindRun/Core/AppState+AppUpdate.swift`、
  `blindRun/Core/Models/AppVersionModels.swift`、`blindRun/Shared/AppUpdateGateModifier.swift`
- 后端：无契约改动。接口已在 `docs/api_spec.yaml`。
- 发布风险：全屏页写错等于把用户锁在外面。判定是纯函数，失败一律不拦，单测逐项钉住。
