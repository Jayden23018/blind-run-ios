## 1. 第 1 批：adapter 与幂等

- [ ] 1.1 新建 `blindRun/Core/SessionAwareAPIClient.swift`：包住任意 `APIClientProtocol`，`requiresAuth` 请求捕获 `.unauthorized` 时先 `await` `@MainActor` 回调再原样重抛
- [ ] 1.2 `AppState.apiClient` 出口（含 `apiClientOverride`）统一包上 adapter；新增只给登出用的未包出口，`logOutOnServer` 改用它
- [ ] 1.3 `handleAuthenticatedAPIError`：已无会话且不在暂缓中时直接返回 true，不再重复 `expireSession()`
- [ ] 1.4 单测（不连真实服务器）：Mock 返回 401 → 不在跑步中登出一次；跑步中进入暂缓；三个并发 401 只登出一次、只写一次过期提示；`requiresAuth: false` 的 401 不登出；登出请求的 401 不写过期提示
- [ ] 1.5 求助触发 / 撤销：`EmergencyCoordinator+Trigger.swift:148`、`+Countdown.swift:141` 收到 `.unauthorized` 时落到「暂缓中被拦」的失败态；补对应单测
- [ ] 1.6 删除账户预检 `AccountDeletionViewModel.swift:46` 去掉直接 `expireSession()` 特例；补单测（跑步中 → 暂缓、不弹删除确认）
- [ ] 1.7 全量 `build-for-testing` 编译；检查断言「401 后仍有会话」的现有用例，按新需求改断言并逐条写进 PR
- [ ] 1.8 security-reviewer 审第 1 批 diff，CRITICAL / HIGH 修完再合

## 2. 第 2 批：调用方清理（等 #868、#869、#871 合并后开）

- [ ] 2.1 把调用方里的 `handleAuthenticatedAPIError` 调用改成「是 `.unauthorized` 就停下」，`AppState+Session` 以外不再直接操作会话
- [ ] 2.2 加一条守卫（`scripts/hooks/guard.mjs`）：`blindRun/` 下除 `AppState+Session.swift`、`SessionAwareAPIClient.swift` 外出现 `handleAuthenticatedAPIError(` 或 `expireSession(` 就拦
- [ ] 2.3 编译门禁；PR 写明「用例已写，未执行」

## 3. 收尾

- [ ] 3.1 负责人真机跑第 1、2 批新增与改动的用例，执行数不为 0
- [ ] 3.2 全部勾完后归档本变更
