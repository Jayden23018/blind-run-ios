# Legacy Flutter Reference Audit

## 审计边界与结论

本文审计旧 Flutter 项目 `/Users/jerry/A/blind-run/blind-run-frontend`，仅用于帮助新的 Swift 原生 iOS + Spring Boot MVP 理解历史行为、交互意图和已暴露的问题。旧项目不是新 MVP 的 source of truth。

结论：

- 旧项目 `lib/` 是当前可参考的 Flutter 主实现；`src/` 下 React/Firebase 代码是更早期 demo，只能作为历史背景，不应纳入迁移依据。
- 旧 Flutter 可以参考的主要价值在行为层：盲人端大按钮、状态播报、地点/时间输入回退、订单轮询、缺 key/缺定位降级提示、紧急联系人下单前拦截。
- 旧 Flutter 不应作为架构或接口模板：Riverpod 全局状态、go_router 路由壳、WebSocket 派单、Flutter AMap plugin、MethodChannel 配置、旧订单状态名和旧 API 命名均不应迁移。
- 若旧代码与 `docs/01-10` 或 `openspec/changes/add-aidrun-ios-spring-mvp` 冲突，必须以当前 docs/OpenSpec 为准。

## 旧项目结构

旧项目同时保留 Flutter、React/Firebase 和原生壳：

- `lib/`：Flutter 主工程，包含页面、状态、模型、网络仓库、AMap、语音、无障碍组件。
- `src/`：早期 React demo，使用 localStorage/Firebase/Leaflet/Firestore 风格数据，不再是主运行时入口。
- `android/`、`ios/`：Flutter 原生壳及 AMap key 注入相关配置。
- `openspec/changes/*`：旧 Flutter 项目内的历史变更记录，能解释部分复杂逻辑来源，例如志愿者 intake readiness、接单后 ownership 确认、AMap key 注入修复。
- `test/`：覆盖旧项目历史 bug 的测试，尤其是盲人无障碍、实时派单、志愿者接单 handoff、定位 readiness。

新 MVP 开发时应把旧项目视为“参考审计材料”，而不是可迁移模块集合。

## 页面结构与路由

旧 Flutter 使用 `go_router` 和 Riverpod 全局 `AppStateController` 驱动路由守卫。路由如下：

| Route | 页面 | 旧行为 |
| --- | --- | --- |
| `/loading` | `LoadingPage` | 启动/会话恢复中间页 |
| `/login` | `LoginPage` | 手机号 + 验证码登录 |
| `/role-selection` | `RoleSelectionPage` | 选择盲人或志愿者角色 |
| `/settings` | `SettingsPage` | 双角色共用设置页 |
| `/blind` | `BlindDashboardPage` | 盲人首页 |
| `/blind/request` | `RequestRunPage` | 创建预约 |
| `/blind/request/place` | `BlindPlaceSearchPage` | 地点搜索 |
| `/blind/run/:id` | `BlindActiveRunPage` | 盲人订单详情/状态/评价 |
| `/volunteer` | `VolunteerDashboardPage` | 志愿者地图 Tab 和接单大厅 |
| `/volunteer/run/:id` | `VolunteerActiveRunPage` | 志愿者订单执行页 |

旧路由守卫逻辑会根据 bootstrapping、session、role 统一跳转。这个行为可以参考，但实现方式不迁移。新 Swift iOS 应按当前 `docs/08-ios-architecture.md` 使用 SwiftUI + MVVM 的导航与状态分层，不复刻旧 Flutter 的全局 controller。

## 盲人端流程

旧盲人端的可参考行为：

- 首页根据是否有活跃订单切换主按钮：无订单显示“发起预约”，有订单显示“查看当前订单”。
- 预约流程先选地点，再设置出发时间，最后确认预约。
- 地点搜索支持文字输入和语音搜索；搜索结果会读出地点名与地址。
- 时间输入支持语音识别和预设选项，例如“现在出发”“30分钟后”“明天上午”“今天晚上”。
- 创建订单前会加载盲人资料和紧急联系人；没有紧急联系人时阻止下单。
- 盲人订单页每 5 秒刷新订单详情，并在状态变化时 TTS 播报。
- 订单完成后展示好评/一般/差评评价入口。
- 盲人核心页面使用大按钮、语义标签、固定 AI 助手占位按钮和播报协调层。

旧流程和当前 MVP 冲突或缺失处：

- 旧 Flutter 没有完整实现当前 MVP 的 `arrived -> in_progress` 盲人“确认开始服务”动作；旧状态里志愿者点击“我已出发”后才进入类似 en-route/arrived 链路。
- 旧盲人端没有按当前规格完整实现 accepted/arrived/in_progress 的一键求助终态 `emergency`。
- 旧取消逻辑没有当前 MVP 要求的固定取消原因和二次确认规则。
- 旧评分是三档 `RunRating`，当前 MVP 数据模型是可选星级评分。不要直接迁移三档评分模型。
- 旧语音时间解析偏 demo，当前 MVP 明确排除复杂自然语言时间解析，应以系统 DatePicker/明确输入为主。

## 志愿者端流程

旧志愿者端由一个 dashboard 承载多个 Tab：

- 地图 Tab：显示高德地图、当前位置 marker、附近需求列表、可服务开关、实时派单状态和定位诊断。
- 历史 Tab：展示终态订单和积分文案。
- 商城 Tab：展示固定积分和假商品。
- 我的 Tab：展示资料、认证状态、完成行程/进行中/可接订单数量、设置和退出。

旧志愿者执行链路：

- 打开可服务开关后，旧代码会获取定位并上报 `/api/volunteer/location`。
- 定位上报成功后进入 `onlineReady`，再刷新 `/api/orders/available` 和 `/api/orders/mine`。
- Dashboard 每 10 秒刷新订单，定位心跳每 15 秒上报一次。
- 旧代码还会启动 WebSocket，接收 `NEW_ORDER` 后把实时机会合并到 `volunteerAvailableRuns`。
- 接单使用 `respondToOrder(runId, ACCEPT)`，之后刷新“我的订单”和订单详情，确认 `volunteerOwnershipConfirmed` 后才进入 active run 页。
- active run 页按旧状态提供“我已出发”“我已到达集合点”“结束行程”。

不迁移点：

- 当前 MVP 明确不做 WebSocket，志愿者端不应迁移 `RealtimeDispatchService`、`NEW_ORDER` 推送、断线重连或实时机会合并。
- 当前 MVP 不需要 15 秒定位心跳作为接单核心机制；志愿者附近订单应按当前 docs 使用定位权限、当前位置和本地距离排序。
- 旧 dashboard 同时管理地图、定位、轮询、WebSocket、订单合并、商城、资料，职责过重。新 Swift 端应拆成清晰 ViewModel/Service。
- 旧“出发/到达/完成”状态对应关系不等同于当前 MVP 的 `accepted -> arrived -> in_progress -> completed`。

## 订单模型、状态与 API 形状

旧 Flutter 模型 `Run` 合并了订单详情、可接单预览、实时派单 opportunity、志愿者归属和地图补充字段。关键字段包括：

- `id`
- `location` / `address`
- `timeLabel`
- `status`
- `latitude` / `longitude`
- `plannedStart` / `plannedEnd`
- `distanceKm` / `durationMinutes`
- `volunteerPhone` / `blindUserPhone`
- `volunteerOwnershipConfirmed`
- `dispatchTimeoutSeconds` / `dispatchPriority`
- `isRealtimeDispatch`

旧状态与当前 MVP 状态不能直接映射：

| 旧 Flutter `RunStatus` | 旧含义 | 当前 MVP 处理 |
| --- | --- | --- |
| `PENDING_MATCH` | 正在匹配志愿者 | 大致对应 `matching` |
| `PENDING_ACCEPT` | 等待志愿者确认/待接单 | 不作为新状态；当前志愿者接单后应进入 `accepted` |
| `IN_PROGRESS` | 旧代码中常表示志愿者已接单/可出发 | 当前 `in_progress` 只表示盲人确认开始后的服务中 |
| `DRIVER_EN_ROUTE` | 志愿者正在赶来 | 当前可由 `accepted` 的 UI 表达，或按文档进入 `arrived` 前过程，但不新增状态 |
| `DRIVER_ARRIVED` | 志愿者已到达 | 对应当前 `arrived` |
| `COMPLETED` | 已完成 | 对应 `completed` |
| `CANCELLED` | 已取消 | 对应 `cancelled` |
| `REMATCHING` | 重新匹配中 | 当前 MVP 不支持 |
| `NO_VOLUNTEER` | 暂无志愿者响应 | 当前通过 `cancelled + no_volunteer_available` 或 UI 空状态表达 |

当前 MVP 固定状态机是：

`matching -> accepted -> arrived -> in_progress -> completed`

取消：`matching / accepted / arrived -> cancelled`

求助：`accepted / arrived / in_progress -> emergency`

旧 API 形状也不能直接沿用：

- 旧登录：`/api/auth/send-code`、`/api/auth/verify-code`、`/api/auth/me`
- 当前 OpenAPI：`/api/auth/phone-login`、`/api/users/me`
- 旧角色：`POST /api/user/role`
- 当前 OpenAPI：`PATCH /api/users/me/active-role`
- 旧订单列表：`GET /api/orders/mine?role=...`
- 当前 OpenAPI：`GET /api/orders/my`
- 旧接单/婉拒：`POST /api/orders/{id}/respond` with `ACCEPT/DECLINE`
- 当前 OpenAPI：`POST /api/orders/{id}/accept`
- 旧执行动作：`/en-route`、`/arrived`、`/finish`
- 当前 OpenAPI：`/arrive`、`/confirm-start`、`/complete`
- 旧评价：`/review`，三档评分
- 当前 OpenAPI：`/rating`，可选星级评分

旧 `Run.mergedWith()` 和 `volunteerOwnershipConfirmed` 是历史 bug 修复产物，用于避免接单后更薄的详情 payload 覆盖预览坐标和联系方式。新后端应提供清晰 DTO，Swift 端可做防御式保留，但不要把这种全局合并策略当作正常设计。

## 地图、定位与 AMap 配置

旧 Flutter 的 AMap 配置来源较复杂：

- Dart 编译常量：`AMAP_ANDROID_KEY`、`AMAP_IOS_KEY`、`AMAP_WEB_KEY`
- `AMapConfig.load()`：合并 `String.fromEnvironment` 和 `NativeRuntimeService.readAMapConfig()`
- MethodChannel：`aidrun/device`，用于读取原生配置和判断 Android emulator
- 本地环境文件：`.env`、`.env.local`、`.env.amap.local`
- 脚本：`scripts/flutter_run_with_amap.sh`
- Flutter plugin：`amap_flutter_map`、`amap_flutter_location`、`amap_flutter_base`
- Web Service：客户端直连 `restapi.amap.com/v3/assistant/inputtips`

旧地图/定位行为：

- 没有 native key 时，地图显示占位，不白屏。
- Android emulator 上旧代码会降级，不创建原生地图。
- 定位使用 `permission_handler` 请求权限，一次定位，iOS timeout 更长。
- 位置失败会暴露错误码、错误信息和诊断字段。
- 地点搜索无 Web key 或请求失败时回退到北京本地演示 POI。

新 MVP 处理建议：

- 按当前 docs 使用 iOS 原生 AMap SDK：`AMap3DMap`、`AMapSearch`、`AMapLocation`。
- AMap key 应放在 ignored local config 或本地 plist/xcconfig 示例中；不要迁移 Flutter MethodChannel 或 Flutter plugin。
- 客户端持有 `AMAP_WEB_KEY` 直连高德 Web Service 只能视为旧项目过渡方案；长期应走服务端代理，不应固化。
- 缺 key、缺定位、模拟器无定位时的“可诊断降级提示”可以参考，但不要继续用北京固定点冒充真实 pickup。

## 登录、资料与紧急联系人

旧 Flutter 登录与资料逻辑：

- 手机号格式校验：大陆 11 位手机号正则。
- 旧登录分两步：发送验证码、校验验证码。
- JWT/session 存在 `SharedPreferences`，字段为 token、userId、role。
- 启动时读取本地 session，调用 `/api/auth/me` 校验当前用户。
- `submitRole()` 会调用旧 `/api/user/role`，可能返回替换 token。
- 盲人资料旧接口：`/api/blind/profile`，字段 `name`、`runningPace`、`specialNeeds`。
- 志愿者资料旧接口：`/api/volunteer/profile`，字段 `name`、`verificationStatus`、`availableTimeSlots`。
- 紧急联系人旧接口是独立资源：`/api/users/{userId}/emergency-contacts`，支持列表、新增、更新、删除、设为主要联系人。
- 创建盲人订单前会加载资料和联系人；联系人为空时抛出“请先添加至少一个紧急联系人”。

当前 MVP 应以 OpenAPI 为准：

- 登录：`POST /api/auth/phone-login`，固定验证码 `123456`。
- 当前用户：`GET /api/users/me`。
- 切换角色：`PATCH /api/users/me/active-role`，有 active order 时由后端阻止。
- 盲人资料：`PUT /api/profiles/blind-runner`，必填 nickname 和 emergencyContact。
- 志愿者资料：`PUT /api/profiles/volunteer`，Mock 认证走 `/api/volunteer/mock-verification/approve`。
- Token 存储 MVP 可用 UserDefaults；正式版迁移 Keychain。

## 历史复杂点与潜在 Bug 来源

以下旧实现曾经或容易导致不稳定，不能照搬：

- 志愿者 intake readiness：旧代码最初把本地 `volunteerAvailable` 开关误当成真实在线，后来拆出 `offline/connecting/onlineReady/locationUnavailable/reportFailed`。新实现应区分“用户愿意接单”和“定位/后端已准备好”。
- 接单后 ownership 确认：旧代码需要在 `accept` 后刷新 owned order，确认 `volunteerOwnershipConfirmed`，否则会出现“待接单 + 无权查看”矛盾状态。
- 预览字段与详情字段合并：旧 available order 可能有坐标/电话，owned/detail payload 反而更薄，导致地图坐标丢失。新后端 DTO 应避免这种不一致。
- 北京默认地图 fallback：旧地图曾用北京默认坐标兜底，容易被误认为真实集合点。新实现应显示明确的“定位不可用/坐标不可用”状态。
- AMap key 多来源：旧项目横跨 Dart define、原生层、MethodChannel、脚本和环境文件，容易出现 Dart 认为有 key、原生 SDK 没 key 的分叉。
- WebSocket 重连与轮询并存：旧代码同时维护实时派单、可接订单轮询和我的订单列表，造成重复、过期和归属判断复杂。
- 全局 AppStateController：旧 controller 负责登录、路由、订单、资料、设置、地图、WebSocket、错误处理，耦合度高。
- 语音/TTS 与读屏重复：旧变更已通过播报协调层缓解，但新 Swift 端仍应避免 TTS 重复朗读整页内容。
- 旧 React/Firebase demo：Firestore snapshot、mock runs、Leaflet 地图、localStorage role 与当前 MVP 架构完全不同。

## 可作为行为参考的旧逻辑

可以参考但需按 Swift/iOS 重新实现：

- 盲人端“一屏一个主任务”的大按钮设计。
- 进入关键页面和订单状态变化时的 TTS 播报。
- VoiceOver label/hint 覆盖主按钮、返回按钮、地点候选、状态卡片、评价按钮。
- 地点语音输入失败后保留文字搜索回退。
- 时间语音输入失败后保留预设选项或系统输入回退。
- 订单详情页 5 秒轮询，并在页面离开时停止。
- 创建订单前校验盲人资料和紧急联系人。
- 地图缺 key、定位失败、权限拒绝时显示明确诊断文案。
- 志愿者接单后必须等待后端确认归属再进入执行页。
- 空状态文案应区分“真的没有订单”和“当前尚未准备好接单/定位失败”。

## 不应迁移的旧逻辑

不要迁移以下内容：

- Flutter/Riverpod/go_router 架构。
- 全局 `AppStateController` 聚合所有业务状态的模式。
- Flutter AMap plugin、Flutter MethodChannel 配置读取、Android/iOS Flutter 壳相关逻辑。
- WebSocket 实时派单、`NEW_ORDER` opportunity、重连机制、实时派单和轮询合并。
- 旧 React/Firebase/Leaflet demo。
- 旧订单状态：`PENDING_ACCEPT`、`DRIVER_EN_ROUTE`、`DRIVER_ARRIVED`、`REMATCHING`、`NO_VOLUNTEER`。
- 旧 API 命名：`/api/orders/{id}/respond`、`/en-route`、`/arrived`、`/finish`、`/review`。
- 三档评分模型作为唯一评分模型。
- 商城假兑换、固定积分 `+50`、固定余额展示。
- AI 助手占位按钮作为 MVP 必要功能；当前 docs 明确排除 AI 助手。
- 客户端直持 Web Service key 作为长期方案。
- 北京固定坐标作为真实业务 fallback。

## 与当前 MVP 文档/OpenSpec 的冲突处理

冲突处理原则：

- 以 `docs/01-product-requirements.md`、`docs/02-mvp-scope.md`、`docs/04-user-flows-and-state-machine.md`、`docs/05-page-specs.md`、`docs/06-data-model.md`、`docs/07-api-contract.openapi.yaml`、`docs/08-ios-architecture.md`、`docs/09-accessibility-and-voice-guidelines.md` 为准。
- 以 `openspec/changes/add-aidrun-ios-spring-mvp` 下的 active specs 为准。
- 旧 Flutter 只在行为参考层提供补充，不允许覆盖当前状态机、API contract、数据模型、技术栈和 non-goals。

重点冲突：

| 主题 | 旧 Flutter | 当前 MVP |
| --- | --- | --- |
| 客户端技术 | Flutter 双端 | Swift 原生 iOS |
| 后端集成 | 已接线上旧接口，接口名有漂移 | Spring Boot REST，OpenAPI v0.3 |
| 实时通信 | WebSocket + 轮询并存 | 不做 WebSocket，订单页轮询 |
| 状态机 | `PENDING_*`、`DRIVER_*` 等旧状态 | `matching/accepted/arrived/in_progress/completed/cancelled/emergency` |
| 盲人开始服务 | 旧流程缺少完整确认开始服务 | `arrived -> in_progress` 必须由盲人确认 |
| 紧急求助 | 旧 Flutter 未完整覆盖 | accepted/arrived/in_progress 可进入 terminal `emergency` |
| 角色模型 | 单 role session 风格 | 一个手机号可拥有双角色，activeRole 可切换并受活跃订单拦截 |
| AMap | Flutter plugin + MethodChannel + Web key 直连 | iOS 原生 SDK + ignored local config |
| AI 助手 | 盲人端固定占位按钮 | MVP 排除 AI 助手 |
| 商城 | 假商品、假积分 | 积分/商城仅占位，不做兑换 |

因此，新 MVP 实现时应复用旧项目里被验证过的用户体验意图，而不是复用旧代码、旧状态或旧接口。
