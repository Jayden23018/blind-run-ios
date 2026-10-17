# auth-account-lifecycle Specification

## Purpose
TBD - created by archiving change harden-auth-account-lifecycle. Update Purpose after archive.
## Requirements
### Requirement: Stored sessions are validated before authenticated routing
The iOS app SHALL validate a restored JWT with `GET /api/auth/me` before it connects an authenticated WebSocket or presents a role-specific authenticated flow.

#### Scenario: Stored session remains valid with an active role
- **WHEN** the app launches with a stored JWT and `/api/auth/me` returns the current active user with role `BLIND` or `VOLUNTEER`
- **THEN** the app SHALL hydrate `currentUser`, `userId`, and `activeRole`
- **AND** the app SHALL then connect the role-appropriate WebSocket and route to the correct profile or home flow

#### Scenario: Stored session remains valid before role selection
- **WHEN** `/api/auth/me` accepts the stored JWT but returns no active role or role `UNSET`
- **THEN** the app SHALL hydrate `currentUser` and `userId`, keep the authenticated session, and route to role selection
- **AND** the app SHALL NOT connect a blind or volunteer WebSocket until role selection returns a replacement role token

#### Scenario: Stored session is revoked or deleted
- **WHEN** `/api/auth/me` rejects the stored JWT because it is expired, blacklisted, or belongs to a deleted account
- **THEN** the app SHALL clear all local session data
- **AND** the app SHALL route to login with an accessible explanation

### Requirement: Users can delete their own account safely
The iOS app SHALL provide an accessible two-stage destructive confirmation that calls `DELETE /api/users/{currentUser.id}` and SHALL clear local state only after backend confirmation.

#### Scenario: Account deletion succeeds
- **WHEN** a user without a blocking active order confirms both deletion stages and the backend confirms soft deletion
- **THEN** the app SHALL disconnect WebSocket, clear all local user data, and return to login
- **AND** the app SHALL state that the phone number can be used to register again according to backend policy

#### Scenario: Active order blocks deletion
- **WHEN** the user has an order in a backend-defined blocking status
- **THEN** the app SHALL keep the account and session intact
- **AND** the app SHALL show and speak that the active service must be resolved before deletion

#### Scenario: Account deletion fails
- **WHEN** the delete request fails or cannot be confirmed by the backend
- **THEN** the app SHALL keep local credentials and user state intact
- **AND** the app SHALL offer retry or cancellation without presenting deletion as complete

### Requirement: Rate-limit responses provide actionable retry behavior
The iOS app SHALL handle HTTP 429 separately from generic failures and SHALL use the backend-provided retry interval when available.

#### Scenario: Verification-code request is rate limited
- **WHEN** `POST /api/auth/send-code` returns HTTP 429 with a retry interval
- **THEN** the app SHALL show and speak the backend rate-limit message
- **AND** the send-code control SHALL remain disabled for the authoritative retry interval

#### Scenario: General action is rate limited
- **WHEN** an authenticated operation returns HTTP 429
- **THEN** the app SHALL preserve the current feature state
- **AND** the app SHALL show a retry time without disabling unrelated app features

### Requirement: Session lifecycle actions remain accessible and user-owned
Logout and account deletion SHALL be exposed only for the signed-in blind-runner or volunteer user and SHALL provide VoiceOver labels, hints, loading state, and error announcements.

#### Scenario: Destructive action is in progress
- **WHEN** logout or account deletion is awaiting a backend response
- **THEN** the final destructive control SHALL be disabled against duplicate submission
- **AND** assistive technology SHALL announce that the request is in progress

#### Scenario: Administrative capability is reviewed
- **WHEN** the native user app scope is inspected
- **THEN** it SHALL NOT expose CS login, administrator user deletion, or CS lockout management

### Requirement: The launch disclosure names motion data before it is collected
The app SHALL state, in the first-launch disclosure, that step count, cadence and climbed altitude are recorded from the phone's motion sensor during a run service, what they are used for, and who can see them, because this is a category of personal information added after the previous disclosure version and a consent recorded against the old text does not cover it (PIPL Art. 14).

#### Scenario: Motion data is described as its own disclosure item
- **WHEN** the launch disclosure is presented
- **THEN** it SHALL contain a separate item naming step count, cadence and climbed altitude, so a screen-reader user hears it as its own focus rather than buried in another sentence
- **AND** that item SHALL say the data appears only in the user's own run record and not to the other party
- **AND** that item SHALL say declining the motion permission does not affect the run service

#### Scenario: A device consented under the previous disclosure text
- **WHEN** a device has a recorded launch consent for the previous disclosure version
- **THEN** the launch disclosure SHALL be shown again, because the recorded consent was given for text that did not name motion data

### Requirement: The built-in privacy policy lists motion data and how to turn it off
The built-in privacy policy fallback SHALL list motion data among the collected items, SHALL explain that the Motion & Fitness permission can be turned off in system settings and what is lost when it is, and SHALL say that deleting the account deletes the run records, so that it matches the online policy v1.2 rather than contradicting it.

#### Scenario: Reviewer reads the built-in policy
- **WHEN** the built-in privacy policy is displayed
- **THEN** it SHALL mention step count and the Motion & Fitness permission

### Requirement: 跑步中收到 401 暂缓退出

需要登录的请求返回 401 时，App SHALL 先按「收到 401 先续期再重试一次」处理；只有续期判定登录已失效、原请求仍按 401 失败时才进入下面的处理。本账号的订单处于 `IN_PROGRESS` 时，这种 401 SHALL NOT 清除本地会话、SHALL NOT 退回登录页；App SHALL 进入「登录过期、暂缓退出」状态，直到暂缓结束再按原逻辑登出。订单不处于 `IN_PROGRESS` 时，这种 401 SHALL 照旧清除会话并退回登录页。续期只是暂时不可用（429 / 5xx / 网络）时 SHALL NOT 进入暂缓。

#### Scenario: 跑步中收到 401
- **WHEN** 本账号订单为 `IN_PROGRESS`，订单轮询返回 401，续期返回 `REFRESH_TOKEN_INVALID`
- **THEN** 本地会话保留，不退回登录页，进入暂缓状态

#### Scenario: 不在跑步中收到 401
- **WHEN** 本账号订单为 `DRIVER_ARRIVED` 或没有订单，任一接口返回 401，续期返回 `REFRESH_TOKEN_INVALID`
- **THEN** 清除本地会话并退回登录页，登录页提示登录已过期

#### Scenario: 续期救回来了
- **WHEN** 本账号订单为 `IN_PROGRESS`，订单轮询返回 401，续期成功
- **THEN** 不进入暂缓，轮询用新 access 继续

### Requirement: 暂缓期间停掉需要登录的云端操作并保留本地拨号求助

暂缓期间，订单页 SHALL 停止定时轮询；跑者端求助入口 SHALL 改为本地拨号（主紧急联系人、120、110），弹窗文案 SHALL 说清登录已过期、App 不会代你发送求助；陪跑员跑步中求助面板的紧急按钮 SHALL 改为本地拨号「紧急呼叫」（120、110），弹窗文案 SHALL 说清登录已过期、App 不会代你发送求助，且 SHALL NOT 说「现在不在跑步中」；陪跑员跑步中求助面板里需要登录的另外三行（暂停、让对方手机响、联系客服）SHALL 不可按，副标题 SHALL 说明登录已过期、暂时用不了，SHALL NOT 叫人重试；任何仍然到达的云端求助触发 SHALL 不发出请求并落到失败态，文案以「求助未发出」开头、含「App 不会代你发送求助」与 120、110。界面与播报 SHALL NOT 暗示求助已发出。

#### Scenario: 暂缓期间按求助
- **WHEN** 暂缓期间跑者按下求助
- **THEN** 打开本地拨号弹窗，不调用求助接口

#### Scenario: 陪跑员暂缓期间打开跑步中求助面板
- **WHEN** 暂缓期间陪跑员在跑步中打开求助面板
- **THEN** 紧急按钮标题是「紧急呼叫」而不是「紧急求助」，轻点打开只列 120、110 的本地拨号弹窗，不弹云端求助确认框，不调用求助接口
- **AND** 暂停、响铃、联系客服三行不可按，副标题说登录已过期

#### Scenario: 陪跑员未暂缓时照旧走云端
- **WHEN** 未暂缓时陪跑员在跑步中打开求助面板
- **THEN** 紧急按钮仍是「长按 3 秒，紧急求助」，轻点弹 `AGENTS.md` §6 锁定文案的确认框，另外三行照常可按

#### Scenario: 漏网的云端触发
- **WHEN** 暂缓期间求助协调器收到云端触发
- **THEN** 不调用求助接口，状态为失败态，文案含「未发出」「App 不会代你发送求助」「120」「110」

### Requirement: 暂缓期间可见可听地告知

暂缓期间跑步页 SHALL 在固定底栏里显示常驻提示（SHALL NOT 遮挡求助入口与主按钮）并在进入暂缓时播报一次：跑者端说明「登录已过期，跑完后需要重新登录」与求助降级；陪跑员端说明结束陪跑等操作要先重新登录与求助降级。横幅 SHALL 提供「现在重新登录」按钮。暂缓期间再收到 401 时 SHALL 补念，但 SHALL 限频，不随轮询每次都念。

#### Scenario: 进入暂缓
- **WHEN** 跑步中第一次收到 401
- **THEN** 横幅出现，播报一次过期提示

#### Scenario: 用户主动重新登录
- **WHEN** 暂缓期间用户点「现在重新登录」
- **THEN** 清除会话并退回登录页

### Requirement: 暂缓在跑完或离开订单页时结束

暂缓 SHALL 在以下任一情况结束并按原逻辑登出：本单状态离开 `IN_PROGRESS`（实时推送或本地订单记录任一来源）；跑者从首页导航栈退出订单页；用户点「现在重新登录」。订单页弹出全屏求助界面 SHALL NOT 结束暂缓。

#### Scenario: 实时推送跑完
- **WHEN** 暂缓期间收到本单 `IN_PROGRESS → COMPLETED` 的状态推送
- **THEN** 清除会话并退回登录页

#### Scenario: 跑者返回首页
- **WHEN** 暂缓期间跑者从订单页返回首页
- **THEN** 清除会话并退回登录页

#### Scenario: 弹出求助界面
- **WHEN** 暂缓期间订单页弹出全屏求助界面
- **THEN** 暂缓保持，会话不清除

### Requirement: 登录拿到的 refresh token 安全保存

登录（`POST /api/auth/verify-code`）与续期（`POST /api/auth/refresh`）响应里的 `refreshToken` SHALL 存进 Keychain（与 access 相同的 `AfterFirstUnlockThisDeviceOnly`），连同本地收到响应的时刻与 `expiresIn`。refresh token SHALL NOT 放进 `Authorization` 头、任何 URL（含 WebSocket `?token=`）、UserDefaults 或日志。登出、注销、续期得到「登录已失效」时 SHALL 删除它。

#### Scenario: 登录后保存
- **WHEN** 登录响应带 `refreshToken` 与 `expiresIn`
- **THEN** Keychain 里保存 refresh token 与有效期，`Authorization` 头仍只带 access

#### Scenario: 退出后清除
- **WHEN** 用户登出或会话被判失效
- **THEN** Keychain 里的 access 与 refresh token 都被删除

### Requirement: 到期前主动续期

access 剩余有效期不足一半时（本地收到响应时刻 + `expiresIn` 算，不解析 JWT），App SHALL 调 `POST /api/auth/refresh` 换一组新 token，并用返回的 `token` 与 `refreshToken` 同时覆盖旧值。检查时机 SHALL 包括每次需要登录的请求发出前（不阻塞该请求）与回到前台。

#### Scenario: 过了半衰期发请求
- **WHEN** 距收到登录响应已超过 `expiresIn` 的一半，App 发出一条需要登录的请求
- **THEN** App 发起一次续期，成功后两个 token 都被新值覆盖

### Requirement: 收到 401 先续期再重试一次

需要登录的请求（含上传）返回 401 时，App SHALL 先续期；续期成功 SHALL 用新 access 把原请求重试**一次**，重试仍是 401 SHALL 按 401 处理、SHALL NOT 再续期。多个请求同时 401 时 SHALL 只发一次续期，其余请求等同一次的结果。Keychain 里的 access 已经不是被拒的那个时 SHALL 直接用它重试、不再续期。

#### Scenario: 续期后重试成功
- **WHEN** 订单轮询返回 401，续期返回 200
- **THEN** 轮询用新 access 重发一次并拿到结果，会话不受影响

#### Scenario: 并发 401
- **WHEN** 三个请求同时返回 401
- **THEN** 只发出一次续期请求，三个请求都用新 access 各重试一次

### Requirement: 续期失败按原因分别处理

续期返回 401（`REFRESH_TOKEN_INVALID`）或 400，或本地没有 refresh token 时，App SHALL 删除 refresh token、SHALL NOT 重试续期，原请求 SHALL 按 401 交给现有处理（跑步中暂缓，否则清会话回登录页并可听地提示「登录已过期」）。续期返回 429、5xx、网络错误或超时时，App SHALL 保留会话、SHALL NOT 退回登录页，原请求按那条错误失败；之后 SHALL 冷却一段时间（429 按 `Retry-After`）再试续期，SHALL NOT 每次轮询都发续期。

#### Scenario: 登录已失效
- **WHEN** 不在跑步中，续期返回 401 `REFRESH_TOKEN_INVALID`
- **THEN** 清除会话并退回登录页，登录页念出登录已过期

#### Scenario: 服务器暂时故障
- **WHEN** 跑步中续期返回 503
- **THEN** 会话保留，不进入暂缓，不退回登录页；冷却期内的下一次轮询不再发续期

### Requirement: 续期不打断正在进行的会话

用续期拿到的新 access 替换旧值时，App SHALL NOT 断开或重连 WebSocket、SHALL NOT 重置陪跑会话与求助状态、SHALL NOT 重新路由当前页面；WebSocket 之后重连时 SHALL 用最新的 access。锁屏卡按钮发出的请求收到 401 时 SHALL 同样续期并重试。

#### Scenario: 跑步中续期
- **WHEN** 跑步中续期成功
- **THEN** WebSocket 连接保持，订单页与求助状态不变，下次重连握手的 `?token=` 是新 access

### Requirement: User logout revokes the backend session
Every user-facing logout action SHALL call `POST /api/auth/logout` with a valid access token before completing local session cleanup. When the stored access token has expired, the app SHALL renew it with `POST /api/auth/refresh` first and then call logout with the new token. Local session cleanup SHALL happen whatever the backend result is, because the user's intent is to sign out.

#### Scenario: Logout succeeds
- **WHEN** the user confirms logout and the backend accepts `POST /api/auth/logout`
- **THEN** the app SHALL disconnect WebSocket and clear all local session, profile, contact, and notification state, including the refresh token
- **AND** the app SHALL return to login

#### Scenario: Access token already expired
- **WHEN** confirmed logout receives HTTP 401 and the refresh token is still valid
- **THEN** the app SHALL renew the session once and retry logout with the new access token
- **AND** the app SHALL then complete local cleanup and return to login

#### Scenario: Session already ended
- **WHEN** confirmed logout receives HTTP 401 and renewal reports `REFRESH_TOKEN_INVALID`
- **THEN** the app SHALL complete the same local cleanup and return to login

#### Scenario: Backend fails to revoke
- **WHEN** confirmed logout returns HTTP 5xx
- **THEN** the app SHALL retry logout once with the same token
- **AND** whatever the retry returns, or if the backend cannot be reached at all, the app SHALL still complete local cleanup and return to login
- **AND** the app SHALL NOT claim that the server-side session was revoked

