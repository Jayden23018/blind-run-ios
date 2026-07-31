# AidRun Data Model

本文档定义“助盲跑 / AidRun”Swift iOS 客户端消费的领域模型与 API DTO。服务端是仓库外部云端服务；本文不规定其数据库或实现技术。

## 1. Design Principles

- iOS 模型字段与后端仓库的 `docs/api_spec.yaml` 保持一致（本仓库不再维护契约，见 `docs/07-api-contract-MOVED.md`）。
- Mock fixtures 使用与云端响应相同的标识符和字段形状。
- 时间字段统一使用 ISO 8601 / UTC 存储，客户端按本地时区展示。
- 经纬度使用 `Double`。
- Token 由后端签发 JWT；iOS 存储在 Keychain（`KeychainTokenStore`，`kSecAttrAccessibleAfterFirstUnlock`）。
- 管理员审核字段保留；真实管理员后台和审核流程按后端契约接入。

## 2. Enumerations

### UserRole

| Value | Description |
| --- | --- |
| `blind_runner` | 盲人跑者 |
| `volunteer` | 志愿者 |

### VerificationStatus / AdminReviewStatus

| Value | Description |
| --- | --- |
| `not_submitted` | 未提交 |
| `pending` | 待审核 |
| `approved` | 已通过 |
| `rejected` | 已拒绝 |

志愿者主注册流程由 `VolunteerRegistrationStatus.currentStep` 和 `canAcceptOrders` 决定。Step1 提交基本信息、`idCardName`、`idCardNumber` 后由后端进行身份证二要素核验；iOS 表单只展示一个“姓名”字段，提交时同时作为 `name` 和 `idCardName`。通过后进入 `STEP_3_FACE_VERIFY` 动作活体认证，前端提交 SDK metaInfo 获取 `certifyId`，再调用 `AliyunFaceAuthFacade.verify` 原生 SDK，SDK 回调后通过 result 接口查询最终结果；该 App SDK 流程不使用 `certifyUrl`。发布合同要求外部后端每次 init 使用 JWT 用户、Step1 已通过的姓名和证件号创建全新的 `ID_PRO` App SDK 尝试（`IDENTITY_CARD`、`MULTI_ACTION`），不得缓存或复用单次 `certifyId`。iOS SDK 诊断仅保留 code、retCode、格式校验后的 retCodeSub、retMessageSub 存在性/长度和 SDK 版本。活体认证结果通过时，外部后端必须原子设置 `STEP_4_COMPLETED` 且 `canAcceptOrders = true`，不再要求课程、学习进度或测验。`STEP_4_TRAINING` 和培训统计字段仅用于遗留合同兼容，新注册不得产生该状态；为兼容旧账号和尚未升级的后端，iOS 将 `STEP_4_TRAINING` 归一化为主注册完成，但仍保持 `isAvailable/wantsDispatch = false`，真实派单资格继续由外部接口响应决定。`verificationStatus` 可用于额外资质证书等兼容状态展示，但不得作为主注册接单门槛。

### RunOrderStatus

| Value | Description |
| --- | --- |
| `PENDING_MATCH` | 系统正在派单 |
| `PENDING_ACCEPT` | 志愿者已接单，待出发 |
| `DRIVER_EN_ROUTE` | 志愿者已出发 |
| `DRIVER_ARRIVED` | 志愿者已到达 |
| `IN_PROGRESS` | 服务进行中 |
| `COMPLETED` | 服务已完成 |
| `CANCELLED` | 已取消 |
| `REMATCHING` | 重新匹配中 |
| `NO_VOLUNTEER` | 无可用志愿者 |

正常流转：`PENDING_MATCH -> PENDING_ACCEPT -> DRIVER_EN_ROUTE -> DRIVER_ARRIVED -> IN_PROGRESS -> COMPLETED`；其中 `DRIVER_ARRIVED -> IN_PROGRESS` 由志愿者调用 `POST /api/orders/{id}/start-service` 触发。

取消流转：盲人端 `PENDING_MATCH / PENDING_ACCEPT -> CANCELLED`，志愿者端 `PENDING_ACCEPT / DRIVER_EN_ROUTE / DRIVER_ARRIVED / IN_PROGRESS -> REMATCHING`；志愿者取消已接单订单后，盲人端可执行 `REMATCHING -> CANCELLED`。

求助入口：当前 iOS release 在 `DRIVER_EN_ROUTE / DRIVER_ARRIVED / IN_PROGRESS` 不显示求助入口。`POST /api/emergency/trigger` 保留为后端合同，可由脚本探针验证；真实 UI 启用需后续安全专项补 GPS、通知、失败提示、合规文案和验收。

### CancellationActor

| Value | Description |
| --- | --- |
| `blind_runner` | 盲人跑者取消 |
| `volunteer` | 志愿者取消 |

### ManualCancellationReason

| Value | Display Text |
| --- | --- |
| `time_conflict` | 时间不合适 |
| `wrong_location` | 地点填写错误 |
| `temporary_issue` | 临时有事 |
| `cannot_contact` | 联系不上对方 |
| `other` | 其他 |

### CancellationReason

| Value | Display Text |
| --- | --- |
| `time_conflict` | 时间不合适 |
| `wrong_location` | 地点填写错误 |
| `temporary_issue` | 临时有事 |
| `cannot_contact` | 联系不上对方 |
| `other` | 其他 |
| `no_volunteer_available` | 预约开始前 30 分钟仍无人接单 |

## 3. Entities

### User

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `id` | UUID/String | Yes | 主键 |
| `phoneNumber` | String | Yes | 唯一手机号 |
| `roles` | Set<UserRole> | Yes | 一个手机号可同时拥有两种身份 |
| `activeRole` | UserRole | No | App 内当前身份；首次登录角色选择前可为空 |
| `createdAt` | Instant | Yes | 创建时间 |
| `updatedAt` | Instant | Yes | 更新时间 |

Rules:

- 首次手机号登录自动创建 `User`，但不强制设置 `activeRole`；App 应进入角色选择页并通过角色切换接口保存当前角色。
- 默认可拥有盲人和志愿者身份；资料完整性由对应业务入口校验。
- 若用户存在 `PENDING_ACCEPT`、`DRIVER_EN_ROUTE`、`DRIVER_ARRIVED`、`IN_PROGRESS` 状态订单，禁止切换 `activeRole`。

### BlindRunnerProfile

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `id` | UUID/String | Yes | 主键 |
| `userId` | UUID/String | Yes | 关联 User，一对一 |
| `nickname` | String | Yes | 盲人昵称 |
| `runningExperience` | String | No | 跑步经验 |
| `verifyStatus` | BlindVerifyStatus | Yes | 实名认证状态，仅 `NOT_VERIFIED` / `VERIFIED` / `FAILED` 三态，**没有 PENDING/审核中** |
| `createdAt` | Instant | Yes | 创建时间 |
| `updatedAt` | Instant | Yes | 更新时间 |

Rules:

- 盲人创建预约前必须有完整资料。
- 紧急联系人是 1..N 关系（1～5 个），不再是资料上的单个 `emergencyContactId` 外键；见下方 EmergencyContact。
- `verifyStatus` 由 `POST /api/blind/verify-identity` 的身份证二要素同步核验产生，客户端读取 `GET /api/blind/profile` 上的该字段为准。**本版本它只是引导性提示，不作为下单门槛**（外部后端 `OrderCreationService` 从不读该字段）；升级为硬门槛需先拿到 `demo/docs/handoff.md` Q1（2026-07-29）的答复和对应错误码。
- 身份证号只在提交时短暂存在于认证 ViewModel 内存中，不进入资料模型、持久化、日志、TTS 或提交后的 accessibility 值。
- 年龄、性别、健康注意事项或头像属于后续资料扩展项，接入前需明确隐私规则。

### EmergencyContact

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `id` | Int64 | Yes | 主键 |
| `userId` | Int64 | Yes | 关联盲人用户 |
| `name` | String | Yes | 紧急联系人姓名（新增时必填） |
| `phone` | String | Yes | 紧急联系人电话（新增时必填）。本人读取时后端返回**明文**（`EmergencyContactResponse.phone`，v1.5.0 起），脱敏由 iOS 展示层负责 |
| `relationship` | String | No | 与盲人的关系 |
| `isPrimary` | Bool | Yes | 是否主联系人 |
| `createdAt` | Instant | Yes | 创建时间 |
| `updatedAt` | Instant | Yes | 更新时间 |

Rules:

- 每个盲人用户 1～5 个紧急联系人，且**有且仅有 1 个 `isPrimary = true`**。
- **「至少 1 个紧急联系人且恰好 1 个主联系人」是盲人下单的硬前置条件。** 外部后端 `OrderCreationService` 自身的前置校验是「盲人用户至少有 1 个紧急联系人」，客户端阻断与之一致并额外保证主联系人唯一。
- 第一个新增的联系人由后端自动设为主联系人。
- 已有 5 个时新增被后端拒绝；只剩 1 个时删除被后端拒绝。两种情况 iOS 都必须先在 UI 阻断并说明原因。
- 设为主联系人是原子操作：后端先清除原主联系人标记再置新的，客户端每次变更后重新拉取完整列表，不做本地推断。
- 归属校验由后端负责：JWT 用户必须与路径 `userId` 一致，且角色为 `BLIND`，否则 403。iOS 不得使用他人 `userId` 拉取联系人。
- 编辑接口是 PATCH 语义：未传的字段保留原值。iOS 在电话未被用户修改时**不提交** `phone` 字段，从而不会把脱敏串写回服务端。
- 展示、TTS 播报和 accessibility 值只使用脱敏电话，不读出完整号码。
- 端点：`GET`/`POST /api/users/{userId}/emergency-contacts`、`PUT`/`DELETE /api/users/{userId}/emergency-contacts/{contactId}`、`PUT /api/users/{userId}/emergency-contacts/{contactId}/set-primary`。
- 自动拨打电话、短信和管理员通知属于生产安全能力，接入前需明确授权、合规文案和后端契约。

### VolunteerProfile

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `id` | UUID/String | Yes | 主键 |
| `userId` | UUID/String | Yes | 关联 User，一对一 |
| `nickname` | String | Yes | 志愿者昵称 |
| `phoneNumber` | String | Yes | 默认来自 User.phoneNumber |
| `verificationStatus` | VerificationStatus | Yes | 志愿者认证状态 |
| `adminReviewStatus` | AdminReviewStatus | Yes | 管理员审核状态 |
| `registrationStep` | VolunteerRegistrationStep | Yes | 主注册流程当前步骤 |
| `canAcceptOrders` | Boolean | Yes | 主注册流程是否已允许接单 |
| `isAvailable` / `wantsDispatch` | Boolean | Yes | “我现在可服务 / 上线接单”开关，控制是否接收系统派单 |
| `pointsBalance` | Integer | Yes | 当前积分余额 |
| `createdAt` | Instant | Yes | 创建时间 |
| `updatedAt` | Instant | Yes | 更新时间 |

Rules:

- 志愿者接收系统派单前必须满足：昵称存在、手机号存在、基本信息/身份证二要素与动作活体认证已完成、主注册流程 `canAcceptOrders = true` 或 `registrationStep = STEP_4_COMPLETED`、`wantsDispatch/isAvailable = true`、WebSocket 在线、已上报最近位置，且符合后端可服务时间和距离规则；课程、测验和可选资质证书不属于主注册接单门槛。
- 可选资质证书上传状态 `verificationStatus` 不影响主流程接单资格；可在个人中心作为加分项展示。
- 关闭可服务开关后不再接收新的系统派单。
- 已接单时关闭开关不影响当前订单。

### LocationPoint

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `latitude` | Double | Yes | 纬度 |
| `longitude` | Double | Yes | 经度 |
| `addressText` | String | No | 手动补充地址或高德逆地理地址 |
| `source` | String | Yes | `device_location` / `manual` / `demo_default` |

Rules:

- 盲人创建订单时默认使用当前位置作为出发点。
- 定位失败时 App 内可使用默认测试坐标辅助演示；真实定位权限仍是核心要求。

### RunOrder

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `id` | UUID/String | Yes | 主键 |
| `blindRunnerUserId` | UUID/String | Yes | 发起订单的盲人用户 |
| `blindRunnerNickname` | String | Yes | 冗余展示字段 |
| `volunteerUserId` | UUID/String | No | 接单志愿者 |
| `volunteerNickname` | String | No | 接单后展示 |
| `status` | RunOrderStatus | Yes | 订单状态 |
| `startLocation` | LocationPoint | Yes | 出发地点 |
| `destinationText` | String | No | 目的地 / 路线说明 |
| `appointmentTime` | Instant | Yes | 预约时间，必须至少当前时间 30 分钟后 |
| `estimatedDurationMinutes` | Integer | No | 预计跑步时长 |
| `estimatedDistanceKm` | Decimal | No | 预计距离 |
| `pacePreference` | String | No | 配速偏好 |
| `preferSameGender` | Boolean | No | 是否需要同性志愿者；当前不参与匹配算法 |
| `remark` | String | No | 备注 |
| `blindRunnerPhone` | String | No | 盲人联系电话；接单前 API 不返回，接单后对接单志愿者完整返回 |
| `createdAt` | Instant | Yes | 创建时间 |
| `acceptedAt` | Instant | No | 接单时间 |
| `arrivedAt` | Instant | No | 到达时间 |
| `startedAt` | Instant | No | 服务开始时间 |
| `completedAt` | Instant | No | 服务完成时间 |
| `cancelledAt` | Instant | No | 取消时间 |
| `emergencyAt` | Instant | No | 求助时间 |
| `updatedAt` | Instant | Yes | 更新时间 |

Rules:

- 只有 `PENDING_MATCH` 订单可被后端系统派单并由被派单志愿者响应；并发/最后一轮多人派单时第一个成功更新为 `PENDING_ACCEPT` 的志愿者获得订单。
- 预约开始前 30 分钟仍无人接单的订单自动进入 `NO_VOLUNTEER`。
- 志愿者排序、扩圈、最后一轮多人派单、全城兜底通知由后端控制；iOS 端不实现匹配算法。
- 接单前隐藏联系方式与紧急联系人；接单后显示盲人完整联系电话。

### Cancellation

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `id` | UUID/String | Yes | 主键 |
| `orderId` | UUID/String | Yes | 关联 RunOrder |
| `cancelledBy` | CancellationActor | No | 用户手动取消时必填；系统超时取消时为空 |
| `cancelledReason` | CancellationReason | Yes | 固定取消原因 |
| `otherReasonText` | String | No | cancelledReason 为 `other` 时填写 |
| `createdAt` | Instant | Yes | 取消时间 |

Rules:

- 盲人跑者可取消 `PENDING_MATCH`、`PENDING_ACCEPT`、`REMATCHING`；`IN_PROGRESS` 盲人端不显示取消入口。
- 志愿者可取消 `PENDING_ACCEPT`、`DRIVER_EN_ROUTE`、`DRIVER_ARRIVED`、`IN_PROGRESS`；取消成功后订单进入 `REMATCHING`，志愿者端退出服务流程。
- 志愿者接单后主动取消会使盲人端订单进入 `REMATCHING`；盲人可用自己的 token 调用 `/api/orders/{id}/cancel` 取消该重新匹配订单，志愿者 token 不适用。
- 用户手动取消原因只能来自 `ManualCancellationReason`。
- 系统超时取消使用 `cancelledReason = no_volunteer_available`，不设置 `cancelledBy`。
- 终态 `COMPLETED`、`CANCELLED`、`NO_VOLUNTEER` 不可取消。
- 志愿者只能在 `DRIVER_ARRIVED` 调用 `/api/orders/{id}/start-service` 开始服务；只能在 `IN_PROGRESS` 调用 `/api/orders/{id}/finish`；`DRIVER_ARRIVED` 不可直接结束。

### EmergencyEvent

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `id` | UUID/String | Yes | 主键 |
| `orderId` | UUID/String | Yes | 关联 RunOrder |
| `triggeredByRole` | UserRole | Yes | 触发求助的角色 |
| `previousStatus` | RunOrderStatus | Yes | 进入求助前状态 |
| `note` | String | No | 可选说明 |
| `createdAt` | Instant | Yes | 触发时间 |

Rules:

- 当前 iOS release 在 `DRIVER_EN_ROUTE`、`DRIVER_ARRIVED`、`IN_PROGRESS` 状态不显示一键求助入口。
- `EmergencyEvent` 保留为后端合同数据；脚本可探测 `POST /api/emergency/trigger`，但 iOS UI 不触发该接口。
- 生产 emergency event UI、GPS 提交、通知和升级处理需后续安全专项重新启用。

### ServiceSummary

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `id` | UUID/String | Yes | 主键 |
| `orderId` | UUID/String | Yes | 关联 RunOrder，一对一 |
| `volunteerUserId` | UUID/String | Yes | 志愿者 |
| `summaryText` | String | No | 志愿者结束服务时选填 |
| `createdAt` | Instant | Yes | 创建时间 |

Rules:

- 当前由志愿者点击“开始服务”进入 `IN_PROGRESS` 后，再点击“结束服务”并可选填服务总结。
- 服务总结只能在订单状态为 `IN_PROGRESS` 时提交；`DRIVER_ARRIVED` 不是可结束状态。

### Rating

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `id` | UUID/String | Yes | 主键 |
| `orderId` | UUID/String | Yes | 关联 RunOrder，一对一 |
| `blindRunnerUserId` | UUID/String | Yes | 评分人 |
| `volunteerUserId` | UUID/String | Yes | 被评分志愿者 |
| `stars` | Integer | Yes | 1 到 5 |
| `comment` | String | No | 可选评价 |
| `createdAt` | Instant | Yes | 创建时间 |

Rules:

- 盲人端在 `COMPLETED` 后可通过 `POST /api/orders/{id}/review` 提交 `CreateReviewRequest(rating, comment)`，也可跳过并返回首页。

- 盲人端可展示星级评分 UI，当前不强制提交。

### VolunteerPointsLedger

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `id` | UUID/String | Yes | 主键 |
| `volunteerUserId` | UUID/String | Yes | 志愿者 |
| `orderId` | UUID/String | No | 完成服务时关联订单 |
| `pointsDelta` | Integer | Yes | 完成一次服务为 `+100` |
| `reason` | String | Yes | 例如 `service_completed` |
| `createdAt` | Instant | Yes | 创建时间 |

Rules:

- 志愿者完成一次服务获得 100 积分。
- 积分商城当前可显示商品入口；真实兑换、库存和支付需要后续契约。

## 4. Relationship Summary

- `User 1 - 0..1 BlindRunnerProfile`
- `User 1 - 0..1 VolunteerProfile`
- `BlindRunnerProfile 1 - 1 EmergencyContact`
- `User(blind_runner) 1 - N RunOrder`
- `User(volunteer) 0..1 - N RunOrder`
- `RunOrder 1 - 0..1 Cancellation`
- `RunOrder 1 - 0..1 EmergencyEvent`
- `RunOrder 1 - 0..1 ServiceSummary`
- `RunOrder 1 - 0..1 Rating`
- `User(volunteer) 1 - N VolunteerPointsLedger`

## 5. Mock Fixture Data for Development

`MockAPIClient` 应提供：

- 至少 1 个盲人用户，资料完整并已有 1～5 个紧急联系人（恰好 1 个 `isPrimary`），可直接下单。
- 至少 1 个盲人用户没有任何紧急联系人，用于验证下单被阻断的引导路径。
- 覆盖 `verifyStatus` 的 `NOT_VERIFIED` / `VERIFIED` / `FAILED` 三态，用于验证实名引导文案；三态都不影响下单。
- 至少 1 个志愿者用户，认证已通过、可服务开关开启。
- 若干 `PENDING_MATCH` 订单，坐标使用可演示的默认测试点。
- 若干已完成订单，用于服务记录与积分页面展示。

## 6. Out of Scope

路线图能力（Android、管理员后台、真实短信、真实实名认证、公共实时轨迹分享、自动电话/短信、AI 助手、自然语言时间解析、路线导航、完整积分商城、支付、库存、App 内聊天、复杂风控、摔倒检测、电子围栏、即时呼叫、多人活动报名）需要先补充产品规则、API 契约和测试计划。订单参与者实时同行位置和完成轨迹总结已由专项 OpenSpec 批准。
## 账户生命周期模型

- `CurrentUserResponse(userId, phone?, role?)`：`role` 可缺省、为 `null` 或 `UNSET`。
- `LogoutResponse(success, message?)`。
- `DeleteAccountResponse(success, message?, phoneReusable, allTokensInvalidated)`。
- `RateLimitInfo(code = RATE_LIMITED, message, rateLimitBucket?, retryAfterSeconds?)`；桶为 `AUTH`、`REGISTRATION`、`GENERAL`，HTTP `Retry-After` 整数秒优先。
- 上述响应不得导致额外敏感信息持久化。

## 实时协调器内存模型

| Model | Required fields | Ownership / lifetime |
| --- | --- | --- |
| `RealtimeOrderRefreshRequest` | `orderId`, `reason` | 协调器按订单合并，Feature ViewModel 完成 REST 刷新后确认 |
| `RealtimeDispatchPrompt` | typed `NEW_ORDER`, `receivedAt`, `expiresAt` | 志愿者会话内保留；响应、过期、失效或角色变化清除 |
| `RealtimeForegroundNotification` | display/speech text, priority, optional stable ID/timestamp, safety flag | 有界队列；HIGH 优先，普通事件去重 |
| `RealtimePeerLocationSample` | `orderId`, owner role, lat/lng, Unix-ms timestamp | 仅内存、按订单/角色；非法/错订单丢弃，不持久化/记录原始坐标 |
| `RealtimeSeparationAlert` | event ID, order ID, safe display/TTS text | 仅路由；策略与动作由后续变更负责 |
| `RealtimeSafetyEvent` | stable event ID, kind, safe display/TTS text | 仅路由；不同稳定 ID 不合并，本期不触发 SOS 动作 |
| `VolunteerLocationFallbackData` | order ID/status/lat/lng/RFC3339 `updatedAt` | pre-service REST 回退；超过 30 秒、错订单/状态或 no-data 不应用 |

这些模型均不成为完整订单、地图/轨迹或 SOS 业务真相；订单真相仍是 `GET /api/orders/{id}`。

## 实时同行与轨迹模型

| Model | Required fields | Rules |
| --- | --- | --- |
| `LocatedCoordinate` | lat, lng, provenance | `wgs84Device` 仅在网络边界转 GCJ-02；`gcj02Backend` 不重复转换 |
| `LiveEscortSession` | order ID, role, canonical status | 仅 `DRIVER_EN_ROUTE` / `DRIVER_ARRIVED` / `IN_PROGRESS` 有效，身份或终态变化即清理 |
| `TrackPoint` | lat, lng, recordedAt | 后端 GCJ-02，按时间升序，不持久化额外副本 |
| `TrackStats` | optional distance/duration/pace | 少于两点时允许 0 / 0 / null，缺字段不推算 |
| `OrderTrackResponse` | status, blind/volunteer track and stats | blind 为主路线；volunteer 只供未来批准的比较策略 |
| `RealtimeEscortAlert` | eventType, messageId, safe display/TTS, active order context | 按外层 eventType 识别两类告警；当前无 orderId，要求唯一 IN_PROGRESS，不改变订单/SOS |

所有当前后端坐标按 GCJ-02 契约解释。数据库无来源字段与历史迁移，但后端确认历史写入均来自高德/腾讯定位链路，现有数据按干净 GCJ-02 使用；未来新增 WGS-84 来源必须在服务端写入边界转换。
