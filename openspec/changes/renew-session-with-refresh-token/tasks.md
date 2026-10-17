## 1. 存储与续期器

- [ ] 1.1 `LoginResponse` 解码 `refreshToken` / `expiresIn`（缺键降级为不续期）；`AuthService.refreshSession`
- [ ] 1.2 Keychain 第二条条目存 refresh token + 签发时刻 + 有效期
- [ ] 1.3 `SessionTokenRefresher`：single-flight、先比对 Keychain、失败分类、冷却、写回前防登出复活

## 2. 接入

- [ ] 2.1 `URLSessionAPIClient` 的 `request` 与 `upload`：发前顺手主动续期，401 续期后重试一次
- [ ] 2.2 `AppState`：登录存凭据、续期写入不走会话重置、`sessionGeneration` 替换 token 当会话身份、登出改为先续期后无论成败都清、回前台主动续期
- [ ] 2.3 WebSocket 重连用新 token；锁屏卡按钮的请求接续期器

## 3. 求助面板（iOS #437）

- [ ] 3.1 暂缓期间暂停 / 响铃 / 联系客服三行不可按，副标题说明登录已过期

## 4. 验证

- [ ] 4.1 单测：续期成功覆盖两个 token、401 不重试、5xx 保留会话、并发只续一次、登出先续期且总会清本地、续期不重置会话；在已提交的基线上验红
- [ ] 4.2 编译门禁通过；真机跑改动覆盖的 suite，`passed=N failed=0`
