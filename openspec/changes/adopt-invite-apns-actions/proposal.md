## Why

后端「派单与邀请模型」第二部分（后端 #369 #370，契约 `websocket-protocol.md`「邀请类 APNs」，iOS #338）：
锁屏 / 杀 App 时邀请只有 APNs，契约给了 `INVITE` / `INVITE_INTRO_CALL` 两个 category 和 `ACCEPT_INVITE` / `DECLINE_INVITE` 两个操作，iOS 没注册。
撤回不会销毁锁屏上的旧通知，点它只会 409。前台时同一条邀请 WS 与 APNs 各来一次。
连续拒绝次数一直本地计：漏了过期、算错了撤回、重装归零；后端已在 `pending-invites` 给 `consecutiveDeclineCount`（SPEC D11）。

## What Changes

- 注册两个 category：`INVITE`（接下 + 这次去不了）、`INVITE_INTRO_CALL`（只有这次去不了）。两个操作都要解锁、**都拉起 App**；「这次去不了」是 destructive。
- 锁屏操作记给协调器，App 前台后等这张邀请进了**当前账号的队列**，翻到它：「接下」走卡片上同一个 `respondToDispatch`
  （定位闸、`INTRO_CALL_REQUIRED` 改发、409 原地失效都在那条路上），「这次去不了」走同一个带 5 秒撤销的 `declineInvite`。
  只认身份对得上的那张（`inviteId`，否则期限）；邀请期限已过、或按下之后的对账里没有它 ⇒ 念「这个邀请已失效，不需要再回复了」。
- 通知中心 delegate 在 `didFinishLaunching` 里设好，`configure` 之前到的锁屏操作先存着；锁屏意图不随 WS 接线时的会话清理抹掉。
- 撤回、本地了结、对账时收掉已送达的邀请通知：按邀请身份收（同单新邀请留着），对账只收早于请求送达、且不在快照里的。
- 前台收到 `NEW_ORDER` APNs：系统横幅不出、不念，改去对一次待回复列表，由 App 内邀请卡呈现；WS 后到按 `inviteId` 去重。
  `INVITE_EXPIRING` 照旧弹出（App 不处理 WS 那一条）。

**为什么不在后台直接回复「去不了」**（第一版就是这么做的，安全复核 HIGH 2 推翻）：后台拉起时根视图未必加载、会话未必恢复，
回复会静默丢失；换账号后还会拿新账号的 token 回复旧账号的通知；点过期的旧通知会按订单拒掉同一单的新邀请。
拉起 App 走卡片路径，三件事都由「只回复当前队列里身份对得上的那张」挡住，并且有可听可见的回执与撤销。
- 连续拒绝改以后端 `consecutiveDeclineCount` 为准，两次对账之间本地先 +1；「问过一次」本地记下问时的次数，再涨 3 才再问，后端清零后从头算；「有意向」同样清零。

## Impact

- 新文件 `blindRun/Core/InviteNotificationActions.swift`；`PushNotificationsManager.swift`（category 注册与操作处理）、`AppDelegate.swift`、`blindRunApp.swift`（启动时设 delegate）
- `AppRealtimeCoordinator.swift`、`AppRealtimeCoordinator+Invites.swift`、`AppState+PendingInvites.swift`
- `VolunteerHomeView.swift`、`VolunteerInviteQueue.swift`、`VolunteerTabView.swift`
- 测试 `blindRunTests/InviteLockScreenActionTests.swift`
- 限制：本机只有免费个人团队，拿不到推送 token（#201），真实推送无法在本机验证；单测守的是推送到达之后的每一步。
