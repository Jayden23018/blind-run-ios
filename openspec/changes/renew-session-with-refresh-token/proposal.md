## Why

access token 固定 24 小时、客户端不会续期：前一天登录、次日开跑，token 会在跑步途中过期，盲人被踢回登录页、WebSocket 断开、云端求助不可用。#376 / PR #382 只是「跑步中不踢下线」的缓解。后端已经上线 refresh token（blind-run-backend#642 / #668，契约见后端 `docs/api_spec.yaml` 的 `POST /api/auth/refresh`），并且**在等 iOS 接完才把 `expiresIn` 从 24 小时改短**（blind-run-backend#669）。

## What Changes

- 登录响应解码 `refreshToken` / `expiresIn`；refresh token 存 Keychain（`ThisDeviceOnly`），不进 `Authorization` 头、不进任何 URL、不进 UserDefaults、不打日志。
- 主动续期：access 剩余有效期不足一半时续（按本地收到响应的时刻 + `expiresIn` 算，不解析 JWT）。检查时机：每次需要登录的请求发出前（不阻塞请求）、回到前台。
- 被动续期：需要登录的请求返回 401 时先续期一次，成功就用新 token 把原请求重试一次；并发的多个 401 只发一次续期（single-flight）。上传接口同样处理。
- 续期结果分类：401 `REFRESH_TOKEN_INVALID` / 400 → 删 refresh token，原请求按 401 处理（交给现有的过期 / 跑步中暂缓逻辑）；429 / 5xx / 网络错误 → **保留会话**，冷却后再试，原请求按那条错误失败。
- 续期**不打断会话**：换 token 不断开 WebSocket、不重置陪跑会话与求助协调器、不重跑根路由；WebSocket 下次重连用新 token。
- 锁屏卡按钮的请求（不经 `AppState`）同样在 401 时续期。
- **BREAKING（行为）** 登出：access 过期时先续期再调 `POST /api/auth/logout`；5xx 原样重试一次；**无论成败都清本地会话**（契约要求，用户的意图是退出）。原来的「服务端退出失败 → 重试 / 仅退出本机」弹窗随之删除。
- 陪跑员跑步中求助面板（iOS #437）：登录过期暂缓期间，「需要停下来 / 让对方手机响 / 联系客服」三行不可按，副标题说明登录已过期。

## Capabilities

### New Capabilities

（无）

### Modified Capabilities

- `auth-account-lifecycle`：新增 refresh token 存储、主动 / 被动续期、续期失败分类、续期不打断会话；改写登出要求；跑步中 401 暂缓改为「续期也救不回来时才暂缓」；暂缓期间陪跑员求助面板三行不可按。

## Impact

- 代码：`blindRun/Core/APIClient.swift`、新增 `blindRun/Core/SessionTokenRefresher.swift`、`AppState.swift`、`KeychainTokenStore.swift`、`WebSocketService.swift`、`GuideRunActivityController.swift`、`Services/AuthService.swift`、`Models/UserModels.swift`、`ContentView.swift`、`blindRunApp.swift`、`Volunteer/VolunteerRunningCompanion.swift`。
- 契约：只用后端已有的 `POST /api/auth/refresh`，不改契约。
- 后端：iOS 发版覆盖后，后端可以把 `jwt.expiration` 改短（blind-run-backend#669）。
- 发布风险：续期分支在真机上只能靠把 access 等到过期来验；单测覆盖续期成功、401 不重试、5xx 保留会话、并发只续一次。
