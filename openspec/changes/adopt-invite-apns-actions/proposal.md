## Why

后端「派单与邀请模型」第二部分（后端 #369 #370，契约 `websocket-protocol.md`「邀请类 APNs」，iOS #338）：
锁屏 / 杀 App 时邀请只有 APNs，契约给了 `INVITE` / `INVITE_INTRO_CALL` 两个 category 和 `ACCEPT_INVITE` / `DECLINE_INVITE` 两个操作，iOS 没注册。
撤回不会销毁锁屏上的旧通知，点它只会 409。前台时同一条邀请 WS 与 APNs 各来一次。
连续拒绝次数一直本地计：漏了过期、算错了撤回、重装归零；后端已在 `pending-invites` 给 `consecutiveDeclineCount`（SPEC D11）。

## What Changes

- 注册两个 category：`INVITE`（接下 + 这次去不了）、`INVITE_INTRO_CALL`（只有这次去不了）。两个操作都要解锁；「接下」另外拉起 App，「这次去不了」是 destructive。
- 锁屏「接下」：记下单号，App 前台后等这张邀请进了队列，翻到它、弹出卡片，走卡片上同一个 `respondToDispatch`（定位闸、`INTRO_CALL_REQUIRED` 改发、409 原地失效都在那条路上）；
  按下之后的对账里没有它 ⇒ 念「这个邀请已失效，不需要再回复了」。
- 锁屏「这次去不了」：后台直接 `POST /respond DECLINE`，成功静默并记为已了结；409 用本地通知说原因（与 App 里「已失效」卡同一套字），前台时念出来。
- 撤回、本地回复、对账时按单号收掉已送达的邀请通知（对账只收早于请求送达、且不在快照里的）。
- 前台收到邀请 APNs：系统横幅不出、不念，改去对一次待回复列表，由 App 内邀请卡呈现；WS 后到按 `inviteId` 去重。
- 连续拒绝改以后端 `consecutiveDeclineCount` 为准，两次对账之间本地先 +1；「问过一次」本地记下问时的次数，再涨 3 才再问，后端清零后从头算；「有意向」同样清零。

## Impact

- 新文件 `blindRun/Core/InviteNotificationActions.swift`；`PushNotificationsManager.swift`（category 注册与操作处理）
- `AppRealtimeCoordinator.swift`、`AppRealtimeCoordinator+Invites.swift`、`AppState+PendingInvites.swift`
- `VolunteerHomeView.swift`、`VolunteerInviteQueue.swift`、`VolunteerTabView.swift`
- 测试 `blindRunTests/InviteLockScreenActionTests.swift`
- 限制：本机只有免费个人团队，拿不到推送 token（#201），真实推送无法在本机验证；单测守的是推送到达之后的每一步。
