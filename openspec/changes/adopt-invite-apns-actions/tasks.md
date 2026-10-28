# Tasks

- [x] 1.1 `InviteNotificationActions`：category / 操作常量、解析 `orderId` / `inviteId` / `expiresAt`、409 说明、已送达通知的筛选。
- [x] 1.2 `PushNotificationsManager`：启动时设 delegate 并注册 category；`configure` 前到的操作先存；前台 `NEW_ORDER` 改走 App 内并对账。
- [x] 1.3 锁屏两个操作：协调器记下（不随会话清理抹掉），首页对上队列里身份相同的那张后走卡片上同一条路径；过期或对账里没有就念已失效。
- [x] 1.4 （第一版的后台回复「去不了」+ 本地通知，经安全复核改为 1.3）。
- [x] 1.5 撤回 / 了结 / 对账时按邀请身份收掉已送达的旧通知。
- [x] 1.6 连续拒绝改用后端 `consecutiveDeclineCount`，问过的记号「再涨 3 才再问」。
- [x] 2.1 单测 `InviteLockScreenActionTests`；`build-for-testing`。
- [ ] 2.2 真机跑 `InviteLockScreenActionTests`、`InviteModelTests`、`blindRunTests`；验红。真实推送在工程团队成员的设备上另验。
