## Why

全仓没有版本检查。2026-11-09 受控公开之后，第一批用户拿到的版本如果不带这个检查，以后就没有办法要求他们升级（#526）。
后端接口已合入（`GET /api/config/app-version`，blind-run-backend#913），但还没部署，线上对这个路径返回 401。
所以客户端必须把一切失败当成「不拦」：这个接口出问题时，不能把所有人挡在 App 外面。

## What Changes

- 启动、登录状态变化、回到前台（`scenePhase == .active`）、陪跑结束时读一次版本要求。
- 当前版本低于 `iosMinSupportedVersion`：系统弹窗，只有「去更新」一个按钮，跳 App Store。回到 App 仍低于最低版本就再弹。
- 当前版本低于 `iosLatestVersion`：系统弹窗，有「稍后」「去更新」两个按钮，同一版本关闭后不再提示。
- 字段缺失、请求失败（含线上现在的 401 和 429）、版本号解析不了、更新地址不是 https：一律不弹。
- 订单处于 `DRIVER_EN_ROUTE`、`DRIVER_ARRIVED`、`IN_PROGRESS`，或有未结束的求助，或者判断不了时：不弹，结束后再弹。

**不做**：不画单独的界面，不放紧急呼叫按钮，文案不提求助（负责人 2026-11-03：「一般来说也不适用一个单独的界面，而是弹窗就可以吧」，
这条覆盖 #526 正文里「全屏提示、保留本地紧急拨号」的要求）。不缓存上一次的结果：缓存会让一次错配置在断网时继续拦人。
不调 `/api/emergency/trigger`。

## 取舍

**三态的判据。** 用现有的 `RunOrderStatus.isEscortUnderway`，它与 `runsLiveEscortSession` 是同一组三个状态。
跑者查 `GET /api/orders/active`，陪跑员查 `dispatch-summary.activeOrders`（后端白名单正好是这三态）。
登录暂缓（#376）和本地同行会话排在网络查询之前。

**代价**：约好但还没出发的订单不让路。这时必须更新的弹窗会挡住订单页，要先更新才能继续用。

**请求排在隐私同意之前。** 这个请求不带任何用户信息、不需要登录，与同意页上的 `legal-links` 同一性质。
必须更新的弹窗不等同意，可关闭的提示等同意之后才弹。

**已知限制。** ① 系统弹窗挂在根视图，用户正开着 sheet 或 fullScreenCover 时弹不出来，要等下一次启动。
② 没有资料的陪跑员查订单得到 404，算「查不清」，不弹：现有错误类型分不出这种 404 和别的 404，判错会挡住正在跑步的人。

## Impact

- Affected specs: 新增 `app-version-gate`
- Affected code: `blindRun/ContentView.swift`、`blindRun/Core/Services/AuthService.swift`、
  `blindRun/Core/AppStatePersistence.swift`、`blindRun/Core/MockAPIClient+AuthenticatedReads.swift`、
  `scripts/openapi/openapi-generator-config.yaml` 与生成代码，
  新增 `blindRun/Core/AppUpdatePolicy.swift`、`blindRun/Core/AppUpdateGate.swift`、`blindRun/Core/AppState+AppUpdate.swift`、
  `blindRun/Core/Models/AppVersionModels.swift`、`blindRun/Shared/AppUpdateGateModifier.swift`
- 后端：无契约改动。接口已在 `docs/api_spec.yaml`。
- 发布风险：必须更新的弹窗写错等于把用户锁在外面。判定是纯函数，失败一律不弹，单测逐项钉住。
