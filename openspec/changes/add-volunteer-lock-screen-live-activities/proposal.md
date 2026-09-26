## Why

陪跑员订单页 v2 只做了 App 内页面。出发去集合点的路上、汇合时站在入口等人、跑步中，陪跑员都不该需要解锁手机看 App。后端 PR-G 已能给出发 / 汇合卡推 `update` / `end`（`docs/live-activity.md`），项目负责人 2026-09-26 在决定源 V3 拍板：出发 / 汇合卡新建、与现有跑步卡并存；跑步卡按交付包 04 最后一节换 v2 样式，继续本地更新（issue #213）。

## What Changes

- 新 Activity 类型 `GuideRunAttributes`（ContentState 与后端推送逐字段一致，`arriveAt` 按 Swift 默认编码即 2001 纪元秒解）。陪跑员订单进 `DRIVER_EN_ROUTE`（按下「我出发了」成功）起卡，`DRIVER_ARRIVED` 换汇合样式，离开两态立即结束。
- 起卡先要 `pushType: .token`，拿到就十六进制上传 `POST /api/devices/live-activity-token`；**系统拒绝时退回本地卡**，App 在前台时随订单轮询与 WS `ORDER_ETA_UPDATED` / `MEET_DISTANCE_BUCKET` 本地更新。2026-09-26 真机实测：本仓库无 APNs 能力，`.token` 被拒（`SessionCore.PermissionsError Code=3`），本期实际走本地更新。
- 卡片按状态换色（出发与快迟到 `stateDeparted`、汇合 `stateArrived`）；只用姓氏（后端姓氏字段未到时不显示名字，不念掩码），整句用「跑者」，不加「先生 / 女士」。
- iOS 17+ 锁屏按钮走 `LiveActivityIntent`：出发时「我快到了」「再等我 5 分钟」（`quick-message`），汇合时「让跑者的手机响起来」（`ring-runner`）；iOS 16 不画按钮。
- 陪跑员端跑步卡 v2：底色 `stateRunning` / 暂停 `statePaused`、第 1 行「陪跑中 · 李：刚刚好」（节奏信号 5 分钟未更新只写「陪跑中」）、「距离 / 目标公里」「用时 · 配速」、8pt 进度条；不画折返线、无按钮。节奏信号与暂停字段做成可选，后端 `run` 对象（BE-1 / BE-2）到之前不显示。跑者端跑步卡不变。
- 状态色常量定义在 widget 共享文件里（widget target 编译不到 `AppColors`），取值同交付包 `01-design-tokens.md`。

## Capabilities

### New Capabilities
- `volunteer-live-activity`: 陪跑员锁屏实时活动 —— 出发 / 汇合卡的起停、推送 token、本地兜底更新、锁屏按钮，以及陪跑员端跑步卡的 v2 样式。

### Modified Capabilities

## Impact

- 代码：`blindRunWidget/Shared/GuideRunActivityShared.swift`（新，双 target）、`blindRunWidget/GuideRunActivityWidget.swift`（新）、`blindRun/Core/GuideRunActivityController.swift`（新）、`RunLiveActivityShared` / `RunLiveActivityWidget` / `RunLiveActivityController` / `LiveEscortSessionCoordinator`（跑步卡 v2）、`VolunteerInServiceViewModel.order`（起卡钩子）、`OrderServing` 加 `registerLiveActivityToken`、`AppState.initialEnvironment`（抽出供 intent 用）、`project.pbxproj` 加两个文件引用（不触及 `DEVELOPMENT_TEAM`）。
- 契约：只读后端 `api_spec.yaml`（`live-activity-token` / `quick-message` / `ring-runner`）与 `docs/live-activity.md`，不改。
- 不在本变更：APNs 能力文件（V2 ②，issue #201）；锁屏「打电话」按钮（锁屏卡只能打开本 App，拨不了 `tel:`）；「已结束」专用样式（widget 拿不到 `activityState`，本地结束一律 `.immediate`）；节奏 / 暂停 / 姓氏的数据接入（FE-3 与 BE-1 / BE-2）。
