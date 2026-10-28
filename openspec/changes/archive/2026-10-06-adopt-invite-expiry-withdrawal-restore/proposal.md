## Why

后端「派单与邀请模型」（SPEC `docs/research/dispatch-invite-model-spec-20260925.md`，PR-1 到 PR-3 已合 main）把派单从
「每人 30 秒串行」改成「一批 3 人并行、回复期限 60 / 15 分钟」，并新增邀请身份 `inviteId`、权威期限 `expiresAt`、
撤回推送 `INVITE_WITHDRAWN`、待回复列表 `GET /api/volunteer/pending-invites`。

iOS 还是按旧模型写的，直接后果：
- 倒计时按秒：「还剩 3599 秒回复」每秒跳一次；紧迫阈值 10 秒，深黄只在最后 10 秒出现（设计稿是「不到 15 分钟」）。
- 撤回推送被当成未知类型丢掉：被同批别人接走的邀请卡一直挂着，「接下」按下去 409，只念一句通用报错，按钮还在。
- 按 `orderId` 去重：撤回后同一张单发来的**新**邀请（新 `inviteId`）被当成重复丢掉。
- 锁屏 / 杀 App 期间的新邀请只有 APNs，撤回补读不回来；回前台、重连后没有任何对账。

## What Changes

- `WSNewOrder` 接 `inviteId` / `expiresAt` / `sentAt`；`type` 改为可选（待回复列表的每一项没有它）。
- 期限以 `expiresAt` 为准；老服务端没有时退回「发出时刻 + 秒数」。邀请身份按 `inviteId` 认，同单新邀请替掉旧的。
- 倒计时一分钟以上按分钟（向上取整），最后一分钟按秒；紧迫阈值改为不到 15 分钟（设计稿）。
- 接 `INVITE_WITHDRAWN`（开放枚举 `reason`）：正在看的那张原地变「这个邀请已失效」并说原因，其余静默移除；
  只移走同一张（`inviteId` 对得上）。
- 「接下」被 409 拒：`ORDER_ALREADY_ACCEPTED` → 原地失效「已有其他陪跑员接下」；`ORDER_DISPATCH_MISMATCH` → 原地失效「回复时间已过」。
  不再留一个必定失败的按钮。`ORDER_DISPATCH_MISMATCH` 的通用文案改为「这个邀请已失效，回复时间已过。」
- 冷启动、回前台、WS 重连后各对一次待回复列表：补进缺的；请求发出前就在手上、快照里没有的判失效。
- `INVITE_EXPIRING` 不处理（契约：找不到卡就忽略，期限视觉由倒计时负责）。
- Mock：`pending-invites` 默认空列表；UI 测试种了邀请时返回同样那几张。

**不做**（下一个变更）：`consecutiveDeclineCount` 改用后端计数；邀请类 APNs 的 category 与锁屏操作。

## Impact

- `blindRun/Core/Models/WebSocketModels.swift`、`blindRun/Core/WebSocketService.swift`、`blindRun/Core/AppRealtimeCoordinator.swift`
- `blindRun/Core/AppState.swift`、`blindRun/blindRunApp.swift`、`blindRun/Core/Endpoints/OrderEndpoint.swift`、`blindRun/Core/Services/OrderService.swift`
- `blindRun/Volunteer/VolunteerHomeView.swift`、`VolunteerInviteQueue.swift`、`VolunteerInviteSheet.swift`、`VolunteerOrderFlowStep.swift`
- `blindRun/Core/Models/ErrorModels.swift`、`blindRun/Core/MockAPIClient.swift`
- 契约：后端 `docs/websocket-protocol.md` 的 NEW_ORDER / INVITE_WITHDRAWN / INVITE_EXPIRING，`docs/api_spec.yaml` 的 `/api/volunteer/pending-invites`
