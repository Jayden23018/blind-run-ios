# Tasks

- [x] 1.1 `WSNewOrder` 接 `inviteId` / `expiresAt` / `sentAt`，`type` 可选；`WSInviteWithdrawn` 与开放枚举 `InviteWithdrawReason`；`PendingInvitesResponse`。
- [x] 1.2 协调器：期限读 `expiresAt`；按 `inviteId` 去重 / 替换；撤回只移同一张并发布；`reconcilePendingInvites` 移走过期项、补缺、发布快照。
- [x] 1.3 `GET /api/volunteer/pending-invites`；`AppState.restorePendingInvites`（只对陪跑员、单飞、缺键不对账）；冷启动 / 回前台 / 重连三处触发。
- [x] 1.4 首页：结果类型加 `.withdrawn(reason)`；撤回 / 快照 / 409 原地失效（正在看的那张）或静默移除；同单新邀请替换失效卡。
- [x] 1.5 倒计时按分钟、紧迫阈值不到 15 分钟；进度条分母取完整窗口；`ORDER_DISPATCH_MISMATCH` 文案。
- [x] 1.6 Mock `pending-invites`：默认空；UI 测试种子同步返回。
- [x] 2.1 单测（`InviteModelTests`，改写 `VolunteerOrderFlowPresentationTests` 两条）；验红。
- [x] 2.2 `build-for-testing`；真机跑覆盖的 suite 与邀请卡 UI 测试。

> 2026-10-06 新鲜上下文审查：A 档 5 条已修 ——
> A1 首页同步按 `orderId` 过滤，同单新邀请进不来 → 改按邀请身份；
> A2 首页清协调器按 `orderId` 整单清，会删掉刚收下的新邀请 → `clearDispatch` 带 `inviteId`；
> A3 撤销窗口里的对账把刚拒绝的邀请灌回来 → 协调器记「已了结」到原期限为止，`retainDispatch` 跳过；
> A4 到达播报仍按秒念 → 用分钟文案；A5 撤销窗口里被撤回的邀请撤销后复活 → 记下原因，撤销时以「已失效」恢复，且不再发 `DECLINE`。
> B 档修了：失效卡离开当前页后清理、409 时卡片已被收走仍要回应、单飞补跑、对账回来复核会话、Mock 种子期限固定、
> 紧迫按显示分钟判（840 / 841）、播报不重复「这个邀请」、期限两样都缺时沿用 30 秒并留诊断、枚举 `nonisolated`、
> 现行两条「30 秒弹窗」要求改为 MODIFIED。新增 6 条回归用例。**真机测试仍没跑**（设备锁屏）。

> 2026-10-07 真机 iPhone 16 Pro（免费个人团队签名）：
> 验红 —— `withdrawDispatch` 只按 `orderId` 认、`reconcilePendingInvites` 不看 `receivedAt < requestedAt`，跑 `InviteModelTests`
> → `passed=16 failed=2`，红的正是 `testWithdrawalOnlyRemovesTheMatchingInvite` 与 `testReconcileRemovesOnlyStaleInvitesAndAddsMissingOnes`。
> 还原后跑 7 个 suite + 邀请卡 UI 两条 → `passed=485 failed=1`：红的 `testVolunteerHomeReceivesDispatchWhenWebSocketIsAssignedAfterConfigure`
> 断言旧播报「请在30秒内回复」，而本变更有意让播报改用 `replyCountdown`，改用例后重跑 → `passed=19 failed=0`。
