# AidRun MVP v0.3 Data Model

本文档定义“助盲跑 / AidRun”Swift iOS + Spring Boot MVP 的数据模型。若仓库中存在更早产品文档，以 MVP v0.3 冻结口径为准：第一版只做预约型订单闭环、手机号登录、JWT、高德地图/定位、无障碍与语音体验，不扩展即时呼叫、聊天、路线导航、完整后台或真实审核。

## 1. Design Principles

- Demo 数据库使用 H2；后续生产化迁移到 PostgreSQL。
- 主键建议使用 UUID 字符串，方便 iOS Mock、H2 与 PostgreSQL 保持一致。
- 时间字段统一使用 ISO 8601 / UTC 存储，客户端按本地时区展示。
- 经纬度使用 `Double`，后续 PostgreSQL 可迁移到 PostGIS，但 MVP 不依赖空间数据库。
- MVP token 可由后端签发 JWT；iOS MVP 存储在 UserDefaults，正式版替换为 Keychain。
- 管理员审核字段保留，但 MVP 不实现真实管理员后台。

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

MVP 中志愿者完成 Mock 认证后，`verificationStatus` 和 `adminReviewStatus` 均可自动设为 `approved`。

### RunOrderStatus

| Value | Description |
| --- | --- |
| `matching` | 等待志愿者接单 |
| `accepted` | 志愿者已接单 |
| `arrived` | 志愿者已到达 |
| `in_progress` | 服务进行中 |
| `completed` | 服务已完成 |
| `cancelled` | 已取消 |
| `emergency` | 求助 / 异常状态 |

正常流转：`matching -> accepted -> arrived -> in_progress -> completed`。

取消流转：`matching / accepted / arrived -> cancelled`。

求助流转：`accepted / arrived / in_progress -> emergency`，MVP 不支持恢复原状态。

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
- 若用户存在 `accepted`、`arrived`、`in_progress`、`emergency` 状态订单，禁止切换 `activeRole`。

### BlindRunnerProfile

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `id` | UUID/String | Yes | 主键 |
| `userId` | UUID/String | Yes | 关联 User，一对一 |
| `nickname` | String | Yes | 盲人昵称 |
| `runningExperience` | String | No | 跑步经验 |
| `emergencyContactId` | UUID/String | Yes | 关联 EmergencyContact |
| `createdAt` | Instant | Yes | 创建时间 |
| `updatedAt` | Instant | Yes | 更新时间 |

Rules:

- 盲人创建预约前必须有完整资料。
- MVP 不加入年龄、性别、健康注意事项或头像。

### EmergencyContact

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `id` | UUID/String | Yes | 主键 |
| `blindRunnerProfileId` | UUID/String | Yes | 关联盲人资料 |
| `name` | String | Yes | 紧急联系人姓名 |
| `phoneNumber` | String | Yes | 紧急联系人电话 |
| `createdAt` | Instant | Yes | 创建时间 |
| `updatedAt` | Instant | Yes | 更新时间 |

Rules:

- MVP 必须存储紧急联系人。
- MVP 不自动拨打电话、不发短信、不推送管理员通知。

### VolunteerProfile

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `id` | UUID/String | Yes | 主键 |
| `userId` | UUID/String | Yes | 关联 User，一对一 |
| `nickname` | String | Yes | 志愿者昵称 |
| `phoneNumber` | String | Yes | 默认来自 User.phoneNumber |
| `verificationStatus` | VerificationStatus | Yes | Mock 认证状态 |
| `adminReviewStatus` | AdminReviewStatus | Yes | 管理员审核字段，MVP 自动通过 |
| `isAvailable` | Boolean | Yes | “我现在可服务”开关 |
| `pointsBalance` | Integer | Yes | 当前积分余额 |
| `createdAt` | Instant | Yes | 创建时间 |
| `updatedAt` | Instant | Yes | 更新时间 |

Rules:

- 志愿者接单前必须满足：昵称存在、手机号存在、`verificationStatus = approved`、`adminReviewStatus = approved`、`isAvailable = true`。
- 关闭可服务开关后仍可看订单，但不能接新单。
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
| `preferSameGender` | Boolean | No | 是否需要同性志愿者；MVP 不参与匹配算法 |
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

- 只有 `matching` 订单可被接单；并发接单时第一个成功更新为 `accepted` 的志愿者获得订单。
- 预约开始前 30 分钟仍无人接单的订单自动进入 `cancelled`，原因 `no_volunteer_available`。
- 后端 MVP 不负责距离排序；iOS 端按志愿者当前位置与订单出发点计算距离并排序。
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

- 服务开始前可普通取消。
- 用户手动取消原因只能来自 `ManualCancellationReason`。
- 系统超时取消使用 `cancelledReason = no_volunteer_available`，不设置 `cancelledBy`。
- `in_progress` 后不能普通取消，只能进入求助 / 异常状态。

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

- `accepted`、`arrived`、`in_progress` 状态显示一键求助入口。
- 确认求助后订单进入 `emergency`，不恢复。

### ServiceSummary

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `id` | UUID/String | Yes | 主键 |
| `orderId` | UUID/String | Yes | 关联 RunOrder，一对一 |
| `volunteerUserId` | UUID/String | Yes | 志愿者 |
| `summaryText` | String | No | 志愿者结束服务时选填 |
| `createdAt` | Instant | Yes | 创建时间 |

Rules:

- MVP 由志愿者点击“结束服务”并可选填服务总结。

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

- 盲人端可展示星级评分 UI，但 MVP 不强制提交。

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
- 积分商城只显示占位商品，不做兑换、库存或支付。

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

## 5. Seed Data for Demo

Spring Boot 启动时应 seed：

- 至少 1 个盲人用户，资料与紧急联系人完整。
- 至少 1 个志愿者用户，Mock 认证已通过、可服务开关开启。
- 若干 `matching` 订单，坐标使用可演示的默认测试点。
- 若干已完成订单，用于服务记录与积分页面展示。

## 6. Out of Scope

MVP 数据模型不支持：Android、完整管理员后台、真实短信、真实实名认证、真实管理员审核后台、WebSocket、实时轨迹共享、自动打电话、自动发短信、AI 助手、复杂自然语言时间解析、路线导航、完整积分商城、支付、库存、App 内聊天、复杂风控、摔倒检测、电子围栏、即时呼叫、多人活动报名。
