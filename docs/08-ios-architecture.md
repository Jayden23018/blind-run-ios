# AidRun iOS Architecture

本文档定义“助盲跑 / AidRun”iOS 上线版客户端工程架构。若存在旧文档，以 `AGENTS.md` 和 `plan.md` 为准：Swift 原生 iOS、SwiftUI + MVVM、真实地图、真实定位、手机号登录 + JWT、无障碍与语音优先。

## 1. Platform

- Language: Swift
- UI: SwiftUI first, UIKit bridge only when needed for 高德地图 SDK or system APIs
- Minimum OS: iOS 16+
- Architecture: SwiftUI + MVVM
- Networking: `URLSession`
- Token storage: currently an injectable `AppStatePersistence` backed by `UserDefaults`; normal, unit-test, and UI-test domains are isolated. Production hardening should migrate to Keychain with separate production/test service namespaces.
- Map: 高德地图 iOS SDK
- Location: CoreLocation + 高德地图定位能力 as needed
- Voice: `AVSpeechSynthesizer`
- Speech input: iOS Speech framework

## 2. Module Layout

Suggested source groups:

- `Core`: App environment, dependency container, shared models, app state
- `Auth`: phone login, JWT persistence, auth session
- `Role`: active role switch and role guard rules
- `BlindRunner`: blind runner home, profile, booking, order status
- `Volunteer`: volunteer home dispatch workbench, availability, WebSocket dispatch prompts, active orders, service records, points
- `Orders`: order DTOs, order state machine helpers, polling
- `Map`: AMap bridge, current location, markers, distance calculation, external map app navigation launchers
- `Voice`: TTS, repeat current status, speech input helpers
- `Safety`: shared dangerous-action copy/components retained for future emergency enablement; current release uses cancellation, completion, and logout confirmations
- `Profile`: blind runner and volunteer profile forms
- `AppRealtimeCoordinator`: `AppState` 持有的 app-lifetime 解码事件路由、优先队列、去重和重连恢复信号；不持有完整订单或 feature policy

## 3. MVVM Pattern

Views should remain thin:

- SwiftUI `View` renders state and forwards user intent.
- `ViewModel` owns loading state, validation state, API calls, polling, and TTS triggers.
- `Service` objects wrap API and platform capability boundaries.
- DTOs mirror OpenAPI schemas; domain helpers handle display text and state transitions.

Recommended examples:

- `AuthViewModel`: phone and code login.
- `BlindBookingViewModel`: location permission, default start coordinate, booking form validation, create order.
- `BlindOrderStatusViewModel`: coordinator refresh/peer-location outputs, 5-second REST polling, typed volunteer-location fallback, status TTS, cancel, completed/rating UI. Current release hides emergency UI.
- `VolunteerHomeViewModel`: availability, current location, dispatch summary, readiness reasons, temporary points, active/recent orders, retained coordinator dispatch prompts.
- `VolunteerOrderDetailViewModel`: WebSocket location pre-report before accept, respond accept/decline, en-route, arrived, start-service, strict IN_PROGRESS finish gate, cancel. Current release hides emergency UI.
- `VolunteerInServiceViewModel`: active order polling, en-route/arrived/start-service/finish actions, strict IN_PROGRESS finish gate, service-completion refresh.

## 4. API Environment Switch

Development keeps Mock for deterministic UI/XCTest coverage. Every networked run uses the single external cloud service. Mock is not release evidence.

| Environment | Purpose |
| --- | --- |
| `mock` | Local fake data for UI and flow debugging |
| `demoCloud` | Current demo cloud backend at `http://47.114.113.171` |

| Build channel | Scheme / configuration | Allowed environment | Environment UI |
| --- | --- | --- | --- |
| Development | `blindRun-Dev` / `Debug` | `mock`, `demoCloud` | Visible |
| Demo | `blindRun-Demo` / `DemoRelease` | `demoCloud` only | Hidden |
| Production | `blindRun-Prod` / `Release` | `demoCloud` only | Hidden |

Implementation guidance:

- Define `APIEnvironment` with `baseURL` and display name.
- Use one `APIClient` protocol so Mock and real implementations share call sites.
- In Debug development builds, expose a small environment selector in settings or launch configuration.
- Unknown persisted environment values are ignored and the build channel default is used.
- Every build uses the shared Info plist with an ATS exception scoped to `47.114.113.171`.
- Do not add a configurable alternative real-server URL without an explicit environment strategy change.
- Use WebSocket for cloud dispatch, status notifications, and location updates; retain REST polling as the disconnected fallback.

## 5. APIClient

`APIClient` responsibilities:

- Build `URLRequest` with method, path, query, JSON body.
- Attach `Authorization: Bearer <accessToken>` for protected endpoints.
- Decode success DTOs and error envelopes.
- Map backend error codes to user-facing messages and TTS error prompts.
- Keep retry behavior simple; complex offline queues require a separate reliability design.

Token persistence:

- Current implementation reads/writes access token through `AppStatePersistence`. Normal App launches use the standard domain; hosted unit tests use a process-isolated suite; UI tests use a dedicated suite that is cleared on every configured launch. Tests must never access the normal App token/environment domain.
- Store only the JWT and minimal active environment setting.
- Add code comments and docs noting Keychain migration before real user release.

## 6. Auth and Role State

Login:

- Phone login and registration are merged.
- Demo verification code is always `000000`.
- On success, backend returns JWT access token and current user; first login may have no `activeRole`, so the app routes to role selection.

Role switching:

- A single JWT is shared across roles.
- Switching only changes `activeRole`.
- If backend returns `ACTIVE_ORDER_ROLE_SWITCH_BLOCKED`, show and speak a clear explanation.

Root routing:

- `ContentView` 只渲染一个 `RootRoute`。登录态、token、user ID 或角色变化时，先取消上一轮账号恢复任务，再在可操作的“正在恢复账号”页并行读取资料、紧急联系人或志愿者注册状态，最后一次性提交登录、资料完善、角色选择或首页路由。
- 根页面之间不得使用透明度 transition 或隐式 animation；AMap 只在最终首页路由挂载后创建，路由离开时随唯一根页面卸载。
- 恢复失败必须进入独立失败路由并提供重试与退出。迟到的旧账号、旧角色或已取消响应不得覆盖当前路由，也不得把网络失败误判为资料不完整。

## 7. Map and Location

Current requirements:

- Debug、DemoRelease 和 Production 的盲人/志愿者首页、订单详情、服务中及完成轨迹页均显示真实高德地图。首页不使用发布熔断开关；只有 AMap Key 缺失或 UI 测试显式禁用地图时才显示配置故障降级。
- `ContentView` 的单一 `RootRoute` 保证任一时刻只挂载当前角色首页的一张 `MAMapView`；角色切换或离开首页时卸载旧地图。首页网络刷新只更新地图输入，不得通过条件根分支反复创建地图。
- Show current location.
- Show order start marker.
- Calculate volunteer-to-start distance on iOS.

Location permission:

- Booking and accepting system dispatches require location permission.
- If denied, blind runner cannot create booking.
- If denied, volunteer cannot receive or accept system dispatches that depend on latest location.
- Show permission guidance, and use TTS for blind runner error prompts.

Demo fallback:

- Keep default test coordinates in app code or debug config so simulator demos do not fail completely.
- Fallback is for demo stability only; UI must still explain real location permission is required.

AMap keys:

- Store real keys in local config such as `LocalConfig.xcconfig` or local plist.
- Add local config to `.gitignore`.
- Commit an example config file that lists required key names but contains no secrets.

## 8. Polling

`WebSocketService` 只负责 URL、收发、500 ms 串行发送队列、两角色 30 秒心跳、3/6/12/30 秒重连退避、后台 JSON 解码和未知消息容忍。状态/通知消息使用可靠 FIFO 并保持接收顺序；连接中连续位置消息只保留最新一条待发送样本。每个物理 socket 绑定递增 generation，旧 generation 回调不得断开替代连接，同一 generation 只能调度一次重连。服务端 90 秒无消息以 `SESSION_NOT_RELIABLE` 关闭；客户端不另设漏 PONG 次数。`AppRealtimeCoordinator` 对当前 service 恰好订阅一次，service/token/role 替换时清理旧订阅与用户内存状态。页面/ViewModel 不得再订阅 raw `eventPublisher`。

志愿者派单诊断只保存在内存，依次标记 transport connected、`NEW_ORDER` received/decode failed、retained、presented；仅 DEBUG UI 展示角色、generation、消息类型、`orderId`、时间和失败字段。禁止写入 token、坐标、电话、地址或正文。志愿者 socket 重连后由首页 ViewModel 立即补报最新真实位置并刷新权威派单摘要，不从 `/api/orders/available` 自行恢复或接受未定向订单。

首页请求统一使用 `AsyncLoadState`、唯一 request ID、一个可取消的 request group 和 20 秒 deadline。志愿者派单摘要是独立主请求，不等待资料、注册状态、定位上报或传播延迟；辅助请求失败只更新对应提示。超时必须取消整个子任务组并进入可重试失败态，迟到结果不得恢复转圈或覆盖新数据。已有摘要/订单继续显示，刷新错误只作为非阻塞提示。后台、锁屏、导航离开会取消旧组，回前台与 WebSocket 重连刷新合并为一轮。

首页 deadline 由非 MainActor 的 `HomeLoadCoordinator` 使用非阻塞竞速释放 UI，ViewModel 只在 MainActor 接收当前 request ID 的最终结果。首次权威订单尚未确认时，盲人端不得进入新建预约，以避免重复订单；设置、记录、重复状态、地图和重试仍必须可操作。`MainRunLoopWatchdog` 在独立队列采样主 run loop，只记录匿名页面类别与卡顿时长，不记录账号、token、订单内容或坐标。

志愿者订单状态操作（接单、我已出发、已到达、开始服务、完成及取消）使用独立的 12 秒应用层 deadline，覆盖状态 POST 与紧随其后的权威订单 GET。截止时必须取消底层任务、立即释放按钮并提示“操作结果尚未确认”，继续依赖 WebSocket/轮询读取权威状态；客户端不得因超时伪造成功，也不得无限保持提交遮罩。

`OrderStatusReconciler` 是 WebSocket 与 REST 状态候选的唯一内存裁决器，按订单保存当前状态与请求代次。合法关联的 `ORDER_STATUS_CHANGED` 先同步提交页面状态、按钮和播报；较早 REST 请求的回退状态被替换为已接受的新状态。首页、盲人订单页、志愿者详情页和服务页只消费同一裁决结果，不各自推导状态。定位准备、同行会话、位置发送、地图输入和详情恢复在状态提交后的后续执行周期分别调度，任一任务悬挂不得占用 MainActor 或阻断根视图命中。

`AppRealtimeCoordinator` 在当前登录会话内使用最多 256 条 UUID → 订单/状态指纹缓存拦截 `ORDER_STATUS_CHANGED` 重放。完全相同的重放在进入状态协调器前丢弃；同一 UUID 的指纹碰撞不采用任何候选状态，仅允许首次碰撞触发有界 REST 恢复。缓存跨物理 WebSocket 重连保留，在退出登录、token/角色身份替换或协调器会话清理时释放。缺失或非法 UUID 记录匿名合同异常后走既有订单关联与状态协调，以兼容旧消息。

订单生命周期语音只由已校验的结构化状态事件或 REST 降级结果使用客户端本地固定文案触发。活动订单的并行生命周期 `APP_NOTIFICATION` 被抑制；协调器另保留最近 30 秒已应用的目标状态语义，使 `COMPLETED` 等终态卸载订单后到达的模板通知也不会重复朗读。安全告警与非生命周期通知不使用该语义抑制。

同行位置接收按订单与角色保留最新样本，在下一次 MainActor 提交前合并重复/洪泛位置；订单状态与通知事件不合并并保持可靠顺序。性能阶段诊断只记录固定类别、触发来源、结果和耗时，`MainRunLoopWatchdog` 在卡顿记录中附带当前匿名阶段；该诊断禁止账号、JWT、订单号或坐标。

同行位置的新鲜度不由 SwiftUI 周期时间线轮询。盲人订单 ViewModel 与志愿者服务 ViewModel 各自只保留一个 15 秒可取消过期任务：合法新样本替换任务，任务到期前必须再次核对订单和样本身份；页面离开、订单结束或切换订单立即取消并清理。禁止使用 `TimelineView(.periodic(from: .now, ...))` 驱动同行地图，因为动态 `.now` 在 AttributeGraph 重算期间可能不断重建立即到期的时间线并形成高 CPU 刷新环。

`LiveEscortSessionCoordinator.healthState` 只在 `Equatable` 值真正改变时发布。志愿者首页不得把顶部子视图的 `PreferenceKey` 测量结果反写进同一布局图；面板边界由安全区和当前订单是否存在计算为确定值，避免两个有效高度之间振荡。地图 bridge 继续按坐标、annotation 语义内容和屏幕锚点差异更新，不因状态确认或五秒位置节拍重建地图容器。

`MAMapView` 的 UIKit 内部会随渲染持续维护布局、子视图和无障碍元素。`AMapContainer` 向 SwiftUI 返回尺寸稳定的 `AMapHostView`，真实地图只作为该宿主的约束子视图，使内部逐帧布局失效停留在 UIKit；桥接层同时隐藏地图内部无障碍子树，只暴露一个稳定的 SwiftUI 地图摘要。位置、订单和同行状态由页面现有文字区域朗读。`LocationService` 同时区分“最新网络样本”和“页面展示坐标”：静止时的新时间戳仍可供五秒上报复用，但不会仅因时间变化发布整棵环境树，坐标、权限或错误状态未变化时不得触发地图/首页重算。

首页地图渲染设置可自动降帧的低帧率上限，并使用默认 RunLoop mode，让父级 `ScrollView` 跟踪手势时优先响应触摸。`ContentView` 对 `@Published` 通知和同行健康状态的播报使用跨订阅生命周期的身份门禁：Combine 当前值 publisher 会在 SwiftUI 重建订阅时立即重放，不能只依赖单次订阅内的 `removeDuplicates()`；门禁必须先记录通知 UUID/健康枚举再调用 TTS，避免 TTS 的 `@Published` 属性反向触发根视图重算和无限重播。

`URLSessionAPIClient` 只记录脱敏的 endpoint 类别、HTTP 状态、耗时、取消/传输/解码阶段及匿名 request ID；数字资源 ID 归一化为 `{id}`，禁止记录 JWT、手机号、坐标、姓名和响应正文。`RuntimeDiagnosticMonitor` 只读取并汇总 MetricKit 崩溃/卡顿诊断数量，用于区分 watchdog、内存或 Swift 异常，不保存 MetricKit 原始载荷。

`ORDER_STATUS_CHANGED` 在 UUID 去重和状态协调后写入按 order ID 合并的 refresh set；Feature ViewModel 拉取 REST 完整详情以补齐字段并确认服务端持久化。瞬时失败按 1/2/4 秒退避重试，三次重试耗尽后释放请求并保留页面错误/既有轮询降级。`LiveEscortSessionCoordinator` 消费已协调订单、recovery signal 和真实定位，统一管理五秒上报、15 秒新鲜度、后台定位及清理；页面只消费其窄状态和 peer marker。

Blind runner order status pages must poll order details every 5 seconds while status is:

- `PENDING_MATCH`
- `PENDING_ACCEPT`
- `DRIVER_EN_ROUTE`
- `DRIVER_ARRIVED`
- `IN_PROGRESS`

Stop polling when:

- Order reaches `COMPLETED`, `CANCELLED`, or `NO_VOLUNTEER`.
- View disappears.
- User logs out.

## 9. Accessibility and Voice Integration

- Blind runner pages use large, simple controls with primary button height at least 64pt.
- Every key button, input, and status text needs `accessibilityLabel` and `accessibilityHint`.
- Main flow nodes call TTS through a shared `SpeechService`.
- Every key blind runner page has a “重复当前状态” button.
- Dangerous actions require confirmation: cancel order, complete service, logout, and any future re-enabled emergency action.
- Emergency controls are hidden in the current release; production emergency recording UI must be re-enabled by a dedicated safety change.

## 10. Demo Acceptance Flow

The iOS app must support a two-device demo:

1. Blind runner logs in and completes profile.
2. Blind runner creates booking with current location and appointment at least 30 minutes later.
3. Volunteer logs in, completes identity verification and administrator review, then turns availability on.
4. Volunteer sees available order sorted by distance and accepts it.
5. Blind runner polling shows `PENDING_ACCEPT`.
6. Volunteer marks `DRIVER_EN_ROUTE`, then `DRIVER_ARRIVED`.
7. Volunteer starts service with `POST /api/orders/{id}/start-service`, and the order reaches `IN_PROGRESS`.
8. Volunteer completes service with optional summary; iOS must not call `/api/orders/{id}/finish` before `IN_PROGRESS`.
9. Blind runner sees `COMPLETED` and optional rating UI.

## 11. Roadmap Capabilities

Do not implement Android, full admin backend, public real-time track sharing, app chat, AI assistant, App 内路线规划, automatic calls, automatic SMS, complex risk control, fall detection, geofencing, instant call, payment, stock, or full points shop without explicit product rules, API contracts, and acceptance tests. The approved live-escort change is limited to the two order participants and the completed blind-track summary. Real SMS and identity verification are backend-owned capabilities now represented in `docs/07-api-contract.openapi.yaml`; the iOS client may consume those contracts without adding backend code to this repository. 志愿者前往出发地点阶段允许通过 URL Scheme / MapKit 跳转外部地图 App 做步行导航，不涉及新增后端 API。

## 12. Alibaba CloudAuth SDK Packaging

- 志愿者 Step3 使用阿里云原生 App SDK。客户端提交 `metaInfo` 获取 `certifyId`，再调用原生 SDK；不使用 Safari、自拍 multipart 或身份证照片上传。
- 当前供应包是阿里云官方 iOS SDK 聚合版本 `2.3.50`，官方 ZIP MD5 为 `ef124c58ac90e33ea3d652363cc424fb`。升级时必须替换整个选定模块集合，禁止混用不同聚合版本的二进制。
- ID_PRO 必选模块为 `AliyunFaceAuthFacade`、`ToygerService`、`DTFIdentityManager`、`ToygerNative`、`BioAuthEngine`、`DTFUtility`、`VerifyNativeAbility`、`APBToygerFacade`、`faceguard` 和 `APPSecuritySDK`。
- CocoaPods 必须把 `ToygerService.bundle`、`APBToygerFacade.bundle`、`APBToygerFacadeSuitable.bundle` 和 `BioAuthEngine.bundle` 复制到 App 顶层资源；其中 `ToygerService.bundle/toyger.face.dat` 不得缺失或为空。
- 当前流程不使用 OCR、NFC、多因子意愿认证或美颜，因此对应 framework 与 bundle 不进入构建产物，也不为这些能力增加权限。
- SDK 日志只允许记录数值 code、retCode、格式校验后的 subcode、消息存在性/长度及 SDK 版本；禁止输出完整 JWT、身份证号、MetaInfo、certifyId、reason、extInfo 或 bizData。
## 会话生命周期架构

`AppState` 负责显式恢复状态、`/api/auth/me` 校验、按有效角色连接 WebSocket、统一异步注销以及幂等本地清理。视图不得直接清理会话。账户删除使用共享 ViewModel 状态；客户端活动订单预检只用于提示，服务端始终是最终权威。

本地清理覆盖 Token、用户 ID、当前用户、角色、两类资料、注册状态、紧急联系人、通知缓存及按用户隔离的应急恢复元数据。

## 实时同行架构

- `BackendCoordinateNormalizer` 是唯一 WGS-84→GCJ-02 边界；后端订单、REST、peer 和 track 坐标不得二次转换。
- `LiveEscortSessionCoordinator` 由 `AppState` 持有，绑定一个 owned order 和当前角色；终态、账号/token/角色变化、失去参与关系或 WebSocket 替换立即清理。
- `updateOwnedOrder` 只保存最新订单状态并调度异步 reconcile；相同订单/状态重复输入直接合并，不同步启动定位或发送位置。
- 普通定位由应用级生命周期幂等维护，同行协调器不得重复启动 `CLLocationManager`；增强后台模式只在首次进入或离开 `IN_PROGRESS` 时切换。
- 同一时刻最多执行一次同行位置发送；发送期间的新位置覆盖待发样本，完成后只发送最新值，禁止形成无界位置队列。
- `LocationService` 普通策略为 10 米过滤；`IN_PROGRESS` 使用 fitness、高精度、5 米过滤、禁止自动暂停、允许后台和系统指示，离开后恢复。
- Map bridge 支持稳定 ID annotation/polyline；业务层准备盲人主路线与摘要，View 只渲染。
