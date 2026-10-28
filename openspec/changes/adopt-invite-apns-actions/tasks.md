# Tasks

- [x] 1.1 `InviteNotificationActions`：category / 操作常量、解析 `orderId` / `inviteId` / `expiresAt`、409 说明、已送达通知的筛选。
- [x] 1.2 `PushNotificationsManager`：注册 category；前台邀请 APNs 改走 App 内并对账；锁屏操作分派。
- [x] 1.3 锁屏「接下」：协调器记下，首页对上队列后交给宿主走同一条接单路径；对账里没有就念已失效。
- [x] 1.4 锁屏「这次去不了」：后台回复、记为已了结；409 本地通知说原因。
- [x] 1.5 撤回 / 回复 / 对账时收掉已送达的旧通知。
- [x] 1.6 连续拒绝改用后端 `consecutiveDeclineCount`，问过的记号「再涨 3 才再问」。
- [x] 2.1 单测 `InviteLockScreenActionTests`；`build-for-testing`。
- [ ] 2.2 真机跑 `InviteLockScreenActionTests`、`InviteModelTests`、`blindRunTests`；验红。真实推送在工程团队成员的设备上另验。
