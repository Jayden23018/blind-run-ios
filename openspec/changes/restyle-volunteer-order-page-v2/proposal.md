## Why

后端已合入陪跑员订单页 v2 所需的全部能力（出发时刻、ETA、汇合档位、响铃、快捷消息、结束等待，后端 PR #415 #418 #419 #426 #431 #432 #435），设计交付包 `zhumangpao-handoff/`（00–07）把订单页升级为「藏青头卡 + 引导绳 + 右上角求助」。iOS 侧目前一个新字段、新端点都没接，订单页还是 v3 的四步条样式，陪跑员在出发和汇合阶段拿不到最有用的信息（几点出发、还有几分钟、跑者在不在附近）。

## What Changes

- 设计常量：在现有 `FlowPalette` / `FlowMetrics` / `FlowFonts` 上补齐 v2 取值（不新建第二套色板），navy 改为 `#1B2657`；新增 v2 通用组件（主/次/文字按钮、求助胶囊、导航栏、头卡、跑者卡、地点行、快捷回复、在场胶囊、提醒条），每个带 Preview。
- 新增 `RopeView`（引导绳，替代陪跑员订单页上的四步条，步骤只给读屏）与 `DirectionDial`（汇合方位扇形），含状态切换动画、循环动效与「减弱动态效果」降级。
- 数据层：`OrderDetailResponse` 接入 `travelMinutes` `suggestedDepartAt` `departReminderAt` `primaryActionUnlockAt` `eta` `meet` `runnerAtMeetingPoint` `earliestEndWaitAt` `completedTogetherCount` `messageToVolunteer` `guidePreferenceText`；新端点 `end-waiting` `quick-message` `ring-runner`；错误码 `DEPARTURE_TOO_EARLY` `END_WAIT_TOO_EARLY`；WS `ORDER_ETA_UPDATED` `MEET_DISTANCE_BUCKET`、`BLIND_LOCATION_UPDATE.accuracyM`。
- 订单页按状态原地切换：约好（前一晚 / 出发前 30 分钟）、出发、快迟到、汇合（五个距离档位）、等待满 15 分钟、完成、跑者取消。
- **BEHAVIOR CHANGE**：求助胶囊出现在所有陪跑员订单页右上角。`IN_PROGRESS` 走现有云端 SOS，其余状态降级为本地拨号并说明「App 不会代你发送求助」。推翻 2026-09-17「前三态不显示求助」的决定（项目负责人 2026-09-26 拍板）。
- 设计规则例外（2026-09-26 拍板，记入 `docs/ui/design-direction.md`）：主角数字封顶 AX2；陪跑员端出发 / 汇合的循环动效（减弱动态效果时静止）；两列次级按钮（AX 字号下竖排）。

不在本变更：`IN_PROGRESS` 跑步中页面、邀请阶段新接口（SPEC #393）、锁屏实时活动、跑者端响铃 / 播报 / 留言、衣着、集合点地标、敏感词。

## Capabilities

### New Capabilities
- `volunteer-order-page`: 陪跑员订单页 v2 —— 按订单状态原地切换的头卡与引导绳、出发时刻与 ETA、汇合档位与方位、快捷消息、响铃、结束等待、完成页，以及全页求助入口的降级规则。

### Modified Capabilities
（无）

## Impact

- 代码：`blindRun/Core/DesignSystem/*`、`blindRun/Volunteer/VolunteerOrderFlow*.swift`、新文件 `RopeView.swift` `DirectionDial.swift` `FlowV2Components.swift`、`Core/Models/OrderModels.swift` `WebSocketModels.swift` `ErrorModels.swift`、`Core/Endpoints/OrderEndpoint.swift`、`Core/Services/OrderService.swift`、`Core/AppRealtimeCoordinator.swift`、`MockAPIClient+Order.swift`、`HapticFeedback.swift`。
- 契约：只读后端 `origin/main` 的 `docs/api_spec.yaml` / `websocket-protocol.md`，不改契约。
- 共享色：`Flow.navy` 取值变化影响盲人端首页等所有引用处。
- 文档：`AGENTS.md` §6 求助入口清单、`docs/ui/design-direction.md`、`docs/error-codes.json`。
