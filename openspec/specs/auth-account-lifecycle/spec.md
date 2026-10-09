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

### Requirement: User logout revokes the backend token
Every user-facing logout action SHALL call `POST /api/auth/logout` with the current Bearer token before completing local session cleanup.

#### Scenario: Logout succeeds
- **WHEN** the user confirms logout and the backend accepts `POST /api/auth/logout`
- **THEN** the app SHALL disconnect WebSocket and clear all local session, profile, contact, and notification state
- **AND** the app SHALL return to login

#### Scenario: Token is already invalid
- **WHEN** confirmed logout receives HTTP 401 because the token is already expired or revoked
- **THEN** the app SHALL treat the session as unauthenticated
- **AND** the app SHALL complete the same local cleanup and return to login

#### Scenario: Logout cannot reach the backend
- **WHEN** confirmed logout fails because of a network or server error
- **THEN** the app SHALL NOT claim that the token was blacklisted
- **AND** the app SHALL retain the current local session while offering a retryable, spoken error and an explicitly confirmed local-only sign-out option

#### Scenario: User chooses local-only sign-out after revocation failure
- **WHEN** backend logout failed and the user explicitly confirms "仅退出本机"
- **THEN** the app SHALL disconnect WebSocket, clear all local user data, and return to login
- **AND** the app SHALL state that server-side token revocation was not confirmed and SHALL NOT claim that the remote token was blacklisted

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

本账号的订单处于 `IN_PROGRESS` 时，接口返回 401 SHALL NOT 清除本地会话、SHALL NOT 退回登录页；App SHALL 进入「登录过期、暂缓退出」状态，直到暂缓结束再按原逻辑登出。订单不处于 `IN_PROGRESS` 时，401 SHALL 照旧清除会话并退回登录页。

#### Scenario: 跑步中收到 401
- **WHEN** 本账号订单为 `IN_PROGRESS`，订单轮询返回 401
- **THEN** 本地会话保留，不退回登录页，进入暂缓状态

#### Scenario: 不在跑步中收到 401
- **WHEN** 本账号订单为 `DRIVER_ARRIVED` 或没有订单，任一接口返回 401
- **THEN** 清除本地会话并退回登录页，登录页提示登录已过期

### Requirement: 暂缓期间停掉需要登录的云端操作并保留本地拨号求助

暂缓期间，订单页 SHALL 停止定时轮询；跑者端求助入口 SHALL 改为本地拨号（主紧急联系人、120、110），弹窗文案 SHALL 说清登录已过期、App 不会代你发送求助；任何仍然到达的云端求助触发 SHALL 不发出请求并落到失败态，文案以「求助未发出」开头、含「App 不会代你发送求助」与 120、110。界面与播报 SHALL NOT 暗示求助已发出。

#### Scenario: 暂缓期间按求助
- **WHEN** 暂缓期间跑者按下求助
- **THEN** 打开本地拨号弹窗，不调用求助接口

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

