## Context

`URLSessionAPIClient` 每次由 `AppState.apiClient` 新建，401 直接抛 `.unauthorized`，调用方再交给 `AppState.handleAuthenticatedAPIError`（跑步中暂缓，否则过期登出）。锁屏卡按钮（`GuideRunActivityController.backgroundOrderService`）不经 `AppState`，直接读 Keychain 里的 token。

`AppState.accessToken` 的 `didSet` 在值变化时会断开实时通道、重置陪跑会话与求助协调器；`ContentView.rootRoutingKey`、资料加载的过期判断、`sessionIdentityKey` 都直接拿 token 值当「会话身份」。

## Goals / Non-Goals

**Goals:** 按契约续期；续期不打断正在跑的会话；登录真正失效时沿用现有的过期 / 暂缓处理；并发只发一次续期。

**Non-Goals:**
- 不在续期后强制重连 WebSocket（契约：已建立的连接不受影响，重连时用最新的 access）。
- 不处理 WebSocket 关闭码 `1008`（登出 / 强制下线后的关连接），那是另一件事。
- 不改 Mock：Mock 不会因过期返回 401，续期只接在 `URLSessionAPIClient` 上。

## Decisions

**D1 续期器单独成类 `SessionTokenRefresher`（MainActor），`URLSessionAPIClient` 持有可选引用。** 工程默认隔离是 MainActor，single-flight 只需一个 `Task?` 字段，不用锁、不用 actor。续期请求本身走 `AuthService.refreshSession`（`requiresAuth: false`），所以不会递归进续期器。

**D2 先比对 Keychain 再续期。** 收到 401 时，如果 Keychain 里的 access 已经不是被拒的那个（别的请求或锁屏卡刚续过），直接用新的重试，不再发续期。续期成功准备写回前再读一次 Keychain 里的 refresh token：已被删（期间登出）就丢弃结果，防止登出后把凭据写回去。

**D3 续期失败分两类。** `.unauthorized`（续期端点只有 `REFRESH_TOKEN_INVALID` 一种 401）、400 `VALIDATION_ERROR`、本地没有 refresh token → 「失效」：删 refresh token，原请求抛 `.unauthorized`，后面全走现有逻辑（跑步中暂缓 / 否则登出并在登录页念「登录已过期」）。其余（429、5xx、网络、解码失败）→ 「暂时不可用」：保留会话，冷却 15 秒（429 用 `Retry-After`）再试，原请求抛续期那条错误。冷却是为了跑步中每 5 秒一次的轮询不把续期打到 429（每 IP 每分钟 10 次，与登录共用）。

**D4 主动续期不阻塞请求。** 半衰期时旧 access 仍有效，发请求时只「顺手」起一个续期任务。已经过期的情况由 401 那条路兜住（它会等同一个任务）。主动续期得到「失效」只删 refresh token、不踢人：契约说最后一次续出的 access 还能用到它自己过期，到那时的 401 再走登出 / 暂缓。

**D5 换 token 走「续期写入」，不走会话重置。** `AppState` 用一个标志位让 `accessToken.didSet` 只持久化、不重置；新增 `sessionGeneration`（只在登录 / 登出 / 换账号时递增）替换 `rootRoutingKey`、资料加载判据、`sessionIdentityKey` 里的 token 值。WebSocket 只更新下次重连要用的 token。

**D6 refresh token 与签发时刻存同一条 Keychain 条目。** JSON `{refreshToken, issuedAt, expiresIn}`，account `refreshSession`，accessibility 与 access 相同（`AfterFirstUnlockThisDeviceOnly`，锁屏后台也要读）。一条条目保证三者一起换、一起删。

**D7 登出无论成败都清本地。** 契约原文：无论成败，客户端都清本地会话、回登录页。5xx 原样重试一次（服务端什么都还没撤）。原「仅退出本机」确认弹窗不再可达，一并删除。

**D8 锁屏卡复用 App 的续期器。** `AppState` 初始化时把自己的续期器登记到 `SessionTokenRefresher.appSessionRenewer`（weak）；锁屏卡在 App 还没装好时退回一个只读写 Keychain 的独立续期器。两边同时续，后端两次都成功，存最后到的那一对即可（契约原文）。

## Risks / Trade-offs

- 续期分支在真机上只能等 access 真的过期才走到 → 单测打桩覆盖四条关键路径；后端缩短 `expiresIn` 前不会有用户走到续期之外的新路径。
- 登出失败也清本地 → 服务器上的 refresh 还能用 30 天，但本机已没有任何凭据。契约明确接受这一点。
