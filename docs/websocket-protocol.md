# WebSocket 协议文档

> **版本**: v1.4.0 | **更新**: 2026-07-21
> **导入 Postman**: Postman 支持 WebSocket 请求，可直接使用本文档中的 URL 和消息格式

---

## 一、连接

### 1.1 端点

| 角色 | URL | 认证方式 |
|------|-----|---------|
| 盲人用户 | `ws://47.114.113.171/ws/blind?token={jwt}` | URL query param |
| 志愿者 | `ws://47.114.113.171/ws/volunteer?token={jwt}` | URL query param |

这是 iOS 前端唯一允许使用的真实 WebSocket 服务地址。

### 1.2 认证规则

- JWT token 通过 URL query param `?token=xxx` 传递（浏览器 WebSocket API 不支持自定义 header）
- 后端校验 token 有效性 + 角色匹配：
  - 盲人 token 只能连 `/ws/blind`
  - 志愿者 token 只能连 `/ws/volunteer`
- 角色不匹配 → 握手被拒绝（连接失败）
- 已登出的 token → 握手被拒绝
- 同一用户重复连接 → 旧连接自动断开（只保留最新连接）

### 1.3 连接限制

| 限制项 | 值 |
|--------|-----|
| 消息最大大小 | 64 KB |
| 发送频率限制 | 500ms 最小间隔 |
| 心跳 | 两角色每 30s 发送 PING；服务端立即 PONG |
| 服务端空闲关闭 | 90 秒无任何客户端消息时以 `SESSION_NOT_RELIABLE` 关闭 |

### 1.4 断线重连

建议前端实现自动重连机制：
- 重连间隔：3 秒（建议）
- 指数退避：3s → 6s → 12s → 最大 30s
- 重连后重新发送位置上报
- 客户端不按漏 PONG 次数主动断开；收到服务端关闭或 TCP/WS 错误后统一进入上述重连。

### 1.5 坐标与发送规则

- 所有 `lat` / `lng` / `gpsLat` / `gpsLng` 线上字段均约定为 GCJ-02。
- iOS `CLLocationManager` 的 WGS-84 样本必须在唯一网络边界转换一次；服务端不转换，客户端对入站坐标不再转换。
- 服务阶段位置每 5 秒发送，PING 与位置碰撞时按 500 ms 最小间隔串行排队，不得静默丢弃。
- 数据库无 `coord_system` 标记或历史迁移，但后端确认现有写入均来自高德/腾讯定位链路，历史数据按干净 GCJ-02 使用。未来新增原生 GPS/海外 WGS-84 来源必须在服务端写入边界转换。

---

## 二、盲人用户 WebSocket (`/ws/blind`)

### 2.1 客户端 → 服务器

#### LOCATION_UPDATE — 位置上报

订单处于 `DRIVER_EN_ROUTE`、`DRIVER_ARRIVED` 或 `IN_PROGRESS` 时，前端每 5 秒上报盲人真实 GCJ-02 位置。

```json
{
  "type": "LOCATION_UPDATE",
  "lat": 39.9042,
  "lng": 116.4074
}
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| type | string | 是 | 固定值 `"LOCATION_UPDATE"` |
| lat | number | 是 | 纬度，范围 -90 ~ 90 |
| lng | number | 是 | 经度，范围 -180 ~ 180 |

#### PING — 心跳

```json
{
  "type": "PING"
}
```

服务器会立即返回 `PONG`。建议每 30 秒发送一次。

### 2.2 服务器 → 客户端

#### VOLUNTEER_LOCATION_UPDATE — 志愿者实时位置

当订单处于 `DRIVER_EN_ROUTE`、`DRIVER_ARRIVED` 或 `IN_PROGRESS` 状态时，志愿者每次上报位置都会转发给盲人。

```json
{
  "type": "VOLUNTEER_LOCATION_UPDATE",
  "orderId": 123,
  "lat": 39.9050,
  "lng": 116.4080,
  "timestamp": 1716480000000
}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| orderId | number | 当前订单 ID |
| lat | number | 志愿者纬度 |
| lng | number | 志愿者经度 |
| timestamp | number | Unix 时间戳（毫秒） |

**用途**: 在地图上实时显示志愿者位置，方便盲人等待接驳。

#### APP_NOTIFICATION — 通用通知

基于后端模板推送的各种通知消息。

```json
{
  "type": "APP_NOTIFICATION",
  "messageId": "1b857a85-3ad2-407b-af7b-f8fb6e364285",
  "eventType": "ORDER_MATCHED",
  "body": "已为您匹配志愿者张三，他正在确认行程，请稍候",
  "ttsText": "已为您匹配志愿者张三，他正在确认行程，请稍候",
  "priority": "NORMAL",
  "timestamp": "2026-05-23T14:05:00"
}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| messageId | string(UUID) | 必有，位于最外层，用于前台通知去重 |
| eventType | string | 必有，位于最外层；值为后端模板的 `event_type`，用于机器分流 |
| body | string | 通知文本（显示用） |
| ttsText | string | TTS 朗读文本建议；订单生命周期播报以 iOS 本地订单详情文案为准，不直接朗读生命周期模板 |
| priority | string | `"HIGH"` 或 `"NORMAL"` |
| timestamp | string | ISO 格式时间 |

生产通知固定为平铺 `APP_NOTIFICATION`；`messageId`、`eventType` 与 `timestamp` 位于最外层，不存在嵌套 `data`。`eventType` 对所有模板通知必有，值为模板的 `event_type`。`priority` 为 `HIGH` 或 `NORMAL`，`timestamp` 使用带时区的 RFC 3339。iOS 以 UUID `messageId` 去重。

**盲人端常见通知事件**:

| 事件 | body 示例 | priority |
|------|----------|----------|
| 订单被接单 | 志愿者已接单，请按预约时间前往或等待在出发地点 | NORMAL |
| 志愿者出发 | 志愿者{volunteerName}已出发，正在前往出发地点 | NORMAL |
| 志愿者到达 | 志愿者{volunteerName}已到达出发地点 | HIGH |
| 订单完成 | 订单已完成 | NORMAL |
| 重新匹配 | 志愿者已取消，正在重新匹配 | NORMAL |
| 暂无志愿者 | 暂时没有可用志愿者，仍在等待 | NORMAL |
| 邻近感知 | 志愿者距出发地点约100米 | NORMAL |
| 紧急事件触发 | 已收到求助，正在通知志愿者 | HIGH |
| 联系人已通知 | 已通过短信通知您的联系人{contactName}，请保持冷静 | HIGH |

#### ORDER_STATUS_CHANGED — 订单状态变更

```json
{
  "type": "ORDER_STATUS_CHANGED",
  "messageId": "c4a2d3b1-2345-4bcd-8ef0-123456789abc",
  "orderId": 123,
  "fromStatus": "PENDING_ACCEPT",
  "toStatus": "DRIVER_EN_ROUTE",
  "message": "志愿者已出发",
  "ttsText": "志愿者已出发，正在赶往您的位置",
  "priority": "NORMAL",
  "timestamp": "2026-07-23T15:02:35"
}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| messageId | string(UUID) | 必有；同一次状态变更在断线重发时保持相同，用于会话内去重和后端排查 |
| orderId | number | 订单 ID |
| fromStatus | string | 变更前状态 |
| toStatus | string | 变更后状态 |
| message | string | 状态变更说明（显示用） |
| ttsText | string | TTS 朗读文本 |
| priority | string | `"HIGH"` 或 `"NORMAL"` |
| timestamp | string | ISO 格式时间 |

**订单状态流转**:
```
PENDING_MATCH → PENDING_ACCEPT → DRIVER_EN_ROUTE → DRIVER_ARRIVED → IN_PROGRESS → COMPLETED
      ↓              ↓                  ↓                 ↓              ↓
  CANCELLED      CANCELLED          REMATCHING         REMATCHING       REMATCHING/COMPLETED

REMATCHING → CANCELLED（盲人 token 调用 POST /api/orders/{orderId}/cancel）
NO_VOLUNTEER（无可用志愿者）
```

Emergency WebSocket messages remain contract-reserved. In the current iOS release, emergency UI is hidden and does not call `POST /api/emergency/trigger`; backend contract probes may still verify the endpoint. The order status itself is not changed to emergency.

#### EMERGENCY_RESOLVED_BY_VOLUNTEER — 紧急事件志愿者已确认

```json
{
  "type": "EMERGENCY_RESOLVED_BY_VOLUNTEER",
  "eventId": 456,
  "message": "志愿者确认这是一次误触，紧急事件已解除",
  "ttsText": "这是一次误触，紧急事件已解除",
  "priority": "HIGH",
  "timestamp": "2026-05-23T14:31:00"
}
```

#### EMERGENCY_CONTACT_NOTIFIED — 紧急联系人已通知

```json
{
  "type": "EMERGENCY_CONTACT_NOTIFIED",
  "eventId": 456,
  "message": "已通过短信通知您的联系人张三，请保持冷静",
  "ttsText": "已通知你的联系人张三，请保持冷静",
  "priority": "HIGH",
  "timestamp": "2026-05-23T14:32:00"
}
```

#### PONG — 心跳响应

```json
{
  "type": "PONG",
  "timestamp": 1716480000000
}
```

---

## 三、志愿者 WebSocket (`/ws/volunteer`)

### 3.1 客户端 → 服务器

#### LOCATION_UPDATE — 位置上报

志愿者连接 WebSocket 后，持续上报 GPS 位置。系统会自动转发位置给关联的盲人用户。

```json
{
  "type": "LOCATION_UPDATE",
  "lat": 39.9042,
  "lng": 116.4074
}
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| type | string | 是 | 固定值 `"LOCATION_UPDATE"` |
| lat | number | 是 | 纬度，范围 -90 ~ 90 |
| lng | number | 是 | 经度，范围 -180 ~ 180 |

**注意**:
- 只有通过 WebSocket 连接的志愿者才能收到派单（NEW_ORDER）
- 志愿者必须先发送 `LOCATION_UPDATE`；后端只会向符合距离、可服务时间、认证状态、`wantsDispatch/isAvailable=true` 的在线志愿者派单
- 志愿者排序、扩圈、最后一轮多人派单和全城兜底通知由后端控制；iOS 端不实现匹配算法或公开订单池
- `/api/orders/{orderId}/respond` 依赖后端已记录的最近一次 WebSocket 位置
- 位置同时写入 Redis（30s TTL）和 MySQL
- 建议每 5~10 秒上报一次

### 3.2 服务器 → 客户端

#### BLIND_LOCATION_UPDATE — 盲人位置转发

后端在 `DRIVER_EN_ROUTE`、`DRIVER_ARRIVED` 和 `IN_PROGRESS` 将关联订单中盲人每五秒上报的位置转发给志愿者，iOS 仅展示当前订单且不超过 15 秒的新鲜样本。

```json
{
  "type": "BLIND_LOCATION_UPDATE",
  "orderId": 123,
  "lat": 39.9042,
  "lng": 116.4074,
  "timestamp": 1784433600000
}
```

`orderId` 为关联订单，`lat` / `lng` 为 GCJ-02 且必须位于合法范围，`timestamp` 为 Unix 毫秒。

#### PING — 心跳

```json
{ "type": "PING" }
```

服务器立即返回 `{"type":"PONG","timestamp":...}`。志愿者与盲人均每 30 秒发送。

#### NEW_ORDER — 新订单派单通知（核心消息）

串行派单系统向志愿者推送新订单，志愿者必须在 `dispatchTimeoutSeconds` 秒内响应。

```json
{
  "type": "NEW_ORDER",
  "timestamp": "2026-06-30T10:15:30.123",
  "orderId": 123,
  "startAddress": "朝阳公园南门",
  "startLatitude": 39.9342,
  "startLongitude": 116.4740,
  "distanceKm": 2.5,
  "plannedStart": "2026-05-23T14:00:00",
  "plannedEnd": "2026-05-23T15:00:00",
  "dispatchTimeoutSeconds": 30,
  "priority": "HIGH",
  "pacePreference": "MODERATE",
  "hasGuideDog": true,
  "specialNotes": "请在南门入口等候"
}
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| orderId | number | 是 | 订单 ID |
| startAddress | string | 是 | 起点地址 |
| startLatitude | number | 否 | 起点纬度，后端已提供时用于弹窗地图 marker |
| startLongitude | number | 否 | 起点经度，后端已提供时用于弹窗地图 marker |
| distanceKm | number | 是 | 志愿者到起点的距离（公里） |
| plannedStart | string | 是 | 计划开始时间（ISO 格式） |
| plannedEnd | string | 是 | 计划结束时间（ISO 格式） |
| dispatchTimeoutSeconds | number | 是 | 响应超时时间（秒），默认 30 |
| priority | string | 是 | 固定 `"HIGH"` |
| pacePreference | string | 否 | 配速偏好（如 `MODERATE`） |
| hasGuideDog | boolean | 否 | 盲人是否携带导盲犬 |
| specialNotes | string | 否 | 盲人备注 |
| timestamp | string | 否 | 派单消息发送时间 |

**响应方式**: 收到后必须通过 REST API 的 `/respond` 响应，不是通过 WebSocket 回复。接受使用 `action=ACCEPT`，拒绝使用 `action=DECLINE`。如果订单尚未派送给当前志愿者，后端会返回业务错误，例如 `ORDER_DISPATCH_MISMATCH`。

```
POST /api/orders/{orderId}/respond
Authorization: Bearer <token>
Content-Type: application/json

{
  "action": "ACCEPT"
}
```

**超时未响应**: 系统自动视为拒绝，派单给下一位志愿者。

**派单摘要**: 志愿者首页通过 `GET /api/volunteer/dispatch-summary` 展示派单状态、不可接单原因、覆盖范围、当前订单、近期订单和统计。积分系统未完成时，iOS 可临时按 `totalCompleted * 100` 显示积分占位；`totalAccepted` 只表示接受派单次数，不等同于完成次数。

#### APP_NOTIFICATION — 通用通知

```json
{
  "type": "APP_NOTIFICATION",
  "messageId": "a8d2ebf3-4a21-44e6-a89f-c32e647dddb0",
  "eventType": "IDENTITY_VERIFICATION_APPROVED",
  "body": "您的身份证认证已通过",
  "ttsText": "您的身份证认证已通过，请继续下一步人脸验证",
  "priority": "NORMAL",
  "timestamp": "2026-05-23T10:00:00"
}
```

**志愿者端常见通知事件**:

| 事件 | body 示例 | priority |
|------|----------|----------|
| 身份认证通过 | 您的身份证认证已通过 | NORMAL |
| 身份认证拒绝 | 您的身份证认证未通过，原因：{reason} | HIGH |
| 志愿者注册完成 | 注册完成，请返回首页开启可服务状态 | HIGH |
| 订单超时 | 订单已超过结束时间1小时 | HIGH |
| 邻近感知 | 您已到达盲人附近 | NORMAL |

#### ORDER_STATUS_CHANGED — 订单状态变更

与盲人端格式相同。每次订单状态推进时，盲人和志愿者双方均会收到带 UUID `messageId` 的状态变更通知；同一角色连接中的同一次重发保持相同 `messageId`。

#### EMERGENCY_VOLUNTEER_ALERT — 紧急求助告警

生产紧急求助流程恢复后，盲人触发紧急求助时关联的志愿者会收到此消息；当前 iOS release 隐藏求助入口，不触发该消息。

```json
{
  "type": "EMERGENCY_VOLUNTEER_ALERT",
  "eventId": 456,
  "orderId": 123,
  "userId": 1,
  "message": "您陪伴的盲人用户触发了紧急求助，请在30秒内确认情况",
  "ttsText": "盲人用户触发了紧急求助，请在30秒内确认情况",
  "priority": "HIGH",
  "gpsLat": 39.9042,
  "gpsLng": 116.4074,
  "timestamp": "2026-05-23T14:30:00"
}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| eventId | number | 紧急事件 ID |
| orderId | number | 关联订单 ID |
| userId | number | 盲人用户 ID |
| message | string | 告警说明 |
| ttsText | string | TTS 朗读文本 |
| priority | string | 固定 `"HIGH"` |
| gpsLat | number | 盲人 GPS 纬度（可为 null） |
| gpsLng | number | 盲人 GPS 经度（可为 null） |
| timestamp | string | ISO 格式时间 |

**响应方式**: 通过 REST API 确认（注意是 query param，不是 request body）。

```
// 需要帮助
PUT /api/emergency/{eventId}/volunteer-response?action=NEED_HELP
Authorization: Bearer <token>

// 误触
PUT /api/emergency/{eventId}/volunteer-response?action=FALSE_ALARM
Authorization: Bearer <token>
```

#### EMERGENCY_RESOLVED_BY_VOLUNTEER — 紧急事件解决确认

此消息发送给**客服**和**盲人**，志愿者端不会收到。

```json
{
  "type": "EMERGENCY_RESOLVED_BY_VOLUNTEER",
  "eventId": 456,
  "orderId": 123,
  "resolvedBy": "VOLUNTEER",
  "needHelp": false,
  "priority": "HIGH",
  "timestamp": "2026-05-23T14:31:00"
}
```

---

## 四、跨角色高优先级事件

### ESCORT_DISTANCE_ALERT / ESCORT_SIGNAL_LOST — 同行安全提醒

两类告警都使用同一个平铺结构，以下四组 `body` / `ttsText` 是当前冻结契约：

| 后端模板 | 接收角色 | body | ttsText |
| --- | --- | --- | --- |
| `ESCORT_DISTANCE_ALERT` | `BLIND_USER` | 与志愿者的距离似乎有点远 | 你和志愿者的距离似乎有点远，请留在原地，志愿者正在确认位置 |
| `ESCORT_DISTANCE_ALERT` | `VOLUNTEER` | 与盲人用户的距离似乎有点远 | 你和盲人用户的距离似乎有点远，请尽快确认对方位置 |
| `ESCORT_SIGNAL_LOST` | `BLIND_USER` | 暂时无法获取对方位置，正在为你确认安全 | 暂时无法获取志愿者位置，请留在原地，我们正在为你确认安全 |
| `ESCORT_SIGNAL_LOST` | `VOLUNTEER` | 暂时无法获取对方位置，正在为你确认安全 | 暂时无法获取盲人用户位置，请尽快确认对方安全 |

示例：

```json
{
  "type": "APP_NOTIFICATION",
  "messageId": "d66f9169-bb98-4b62-94b0-d42873899d0b",
  "eventType": "ESCORT_DISTANCE_ALERT",
  "timestamp": "2026-07-21T12:00:00+08:00",
  "body": "与志愿者的距离似乎有点远",
  "ttsText": "你和志愿者的距离似乎有点远，请留在原地，志愿者正在确认位置",
  "priority": "HIGH"
}
```

- `type` 固定为 `APP_NOTIFICATION`；`messageId`、`eventType`、`timestamp` 位于最外层，当前仍不下发 `orderId`。
- `eventType` 分别固定为 `ESCORT_DISTANCE_ALERT` / `ESCORT_SIGNAL_LOST`；四组消息均为 `priority: HIGH`。iOS 仅按 `eventType` 机器分流，`body`/`ttsText` 只用于展示和朗读，不再参与识别。
- 因无 `orderId`，iOS 仅在当前账号恰好有一个关联 `IN_PROGRESS` 订单时展示同行安全告警。
- 若未来新增 `orderId`，后端保证它对应告警触发时的当前订单，iOS 届时必须严格匹配。
- iOS 使用服务端 `body` / `ttsText` 高优先级呈现，不改变 `RunOrderStatus`、不触发 SOS、不宣称救援已派出。
- 100 米且连续 2 次是后端当前运行时工程参数，不是已批准的完成轨迹异常评估规则。

### App 生命周期协调规则

- `AppState` 只持有一个 `AppRealtimeCoordinator`，对当前角色 socket 恰好订阅一次；退出、角色/token 或服务替换时清理旧用户内存事件。
- `ORDER_STATUS_CHANGED` 不构造完整订单，但当 `orderId`、`fromStatus` 与 `toStatus` 均通过当前订单关联和枚举/前进校验时，iOS 先提交其状态字段并立即播报，再独立刷新完整 REST 详情。较早 REST 响应不得回退已接受的状态；非法、错误订单、重复或迟到事件只触发安全刷新。
- iOS 在当前登录会话内最多保留 256 条 `ORDER_STATUS_CHANGED` UUID 及订单/状态指纹。相同 UUID、相同指纹的重发直接丢弃，不更新 UI、不重复播报且不触发 REST 刷新；相同 UUID 携带不同订单或状态时不采用内容，只触发一次有界安全刷新。退出登录或切换身份时清空缓存。
- `messageId` 缺失或不是合法 UUID 属于匿名合同异常。为兼容旧服务端消息，iOS 仍执行订单关联与状态协调，不因该字段异常丢弃合法状态。
- 结构化状态事件使用客户端固定无障碍文案完成一次生命周期播报，不直接朗读服务端 `ttsText`。并行到达的生命周期 `APP_NOTIFICATION` 在活动订单期间抑制；终态卸载订单后的 30 秒内继续按目标状态语义抑制，安全告警及非生命周期通知不受影响。
- REST 详情刷新与盲人端五秒轮询继续作为完整字段补充、断线和漏事件降级路径；WebSocket 推送上线不移除该兜底。
- JSON 解码在后台执行器完成；订单状态和通知保持接收顺序。高频同行位置按订单与角色合并后再交给主线程，发送侧连接队列也只保留最新待发位置，可靠状态/通知消息不受位置合并影响。
- `NEW_ORDER` 保留至接受、拒绝、超时、后端状态使其失效或角色改变，页面切换不能丢失。
- 每个物理 WebSocket 使用单调递增的 connection generation；旧 generation 的迟到收发错误、心跳或关闭回调不得改变新连接，一代连接至多存在一个待执行重连。
- iOS 仅在内存中记录脱敏派单阶段：连接、收到 `NEW_ORDER`、解码失败字段、协调器保留、UI 展示。记录可包含角色、状态、generation、消息类型、`orderId` 和时间，但禁止 token、坐标、电话、地址及消息正文。
- 志愿者等待派单时重连成功，应立即补发最新有效真实位置，再刷新 `/api/volunteer/dispatch-summary`；无真实位置时显示并朗读“定位暂不可用，可能无法收到派单”。
- `/api/orders/available` 当前不是丢失定向推送的客户端兜底；后端未冻结“仅返回分配给当前志愿者且仍在响应期内的 offer”前，iOS 不得据此自行抢单。
- 两个方向的位置消息按订单和接收角色校验；错误订单或非法坐标静默丢弃，日志、可见 UI 和无障碍文本不得输出原始坐标。
- `HIGH` 前台通知抢占 `NORMAL`。非安全事件按稳定 ID 或类型/规范化文案/时间去重；不同安全 `messageId` 不合并。
- 重连后协调器请求活动订单与角色摘要刷新，并通知依赖功能恢复各自节奏。传输层继续保持 500 ms 最小发送间隔、3/6/12/30 秒退避、未知消息容忍和 30 秒心跳。

## 五、消息类型速查表

### 盲人端（`/ws/blind`）

| 方向 | type | 触发场景 | priority |
|------|------|---------|----------|
| 发送 | `LOCATION_UPDATE` | eligible 服务状态每 5s | — |
| 发送 | `PING` | 心跳（30s） | — |
| 接收 | `PONG` | 心跳响应 | — |
| 接收 | `VOLUNTEER_LOCATION_UPDATE` | 志愿者位置实时转发 | — |
| 接收 | `APP_NOTIFICATION` | 平铺模板通知（含距离/信号丢失提醒） | HIGH/NORMAL |
| 接收 | `ORDER_STATUS_CHANGED` | 订单状态变更 | HIGH/NORMAL |
| 接收 | `EMERGENCY_RESOLVED_BY_VOLUNTEER` | 志愿者确认紧急事件 | HIGH |
| 接收 | `EMERGENCY_CONTACT_NOTIFIED` | 紧急联系人已通知 | HIGH |

### 志愿者端（`/ws/volunteer`）

| 方向 | type | 触发场景 | priority |
|------|------|---------|----------|
| 发送 | `LOCATION_UPDATE` | 派单位置或 eligible 服务状态每 5s | — |
| 发送 | `PING` | 心跳（30s） | — |
| 接收 | `PONG` | 心跳响应 | — |
| 接收 | `NEW_ORDER` | 串行派单推送 | HIGH |
| 接收 | `BLIND_LOCATION_UPDATE` | 盲人位置实时转发 | — |
| 接收 | `APP_NOTIFICATION` | 平铺模板通知（含距离/信号丢失提醒） | HIGH/NORMAL |
| 接收 | `ORDER_STATUS_CHANGED` | 订单状态变更 | HIGH/NORMAL |
| 接收 | `EMERGENCY_VOLUNTEER_ALERT` | 紧急求助告警 | HIGH |

---

## 六、前端对接 JavaScript 示例

### 5.1 盲人端连接

```javascript
let ws = null;
let reconnectTimer = null;

function connectBlindWS(token) {
  ws = new WebSocket(`ws://47.114.113.171/ws/blind?token=${token}`);

  ws.onopen = () => {
    console.log('盲人 WebSocket 已连接');
    // 启动心跳
    startHeartbeat();
    // 启动位置上报
    startLocationReport();
  };

  ws.onmessage = (event) => {
    const msg = JSON.parse(event.data);
    switch (msg.type) {
      case 'PONG':
        break; // 心跳响应
      case 'VOLUNTEER_LOCATION_UPDATE':
        updateVolunteerMarker(msg.lat, msg.lng); // 更新地图标记
        break;
      case 'ORDER_STATUS_CHANGED':
        handleOrderStatusChange(msg);
        break;
      case 'APP_NOTIFICATION': {
        showNotification(msg.body, msg.ttsText);
        if (msg.ttsText) speakTTS(msg.ttsText); // 语音播报
        break;
      }
      case 'EMERGENCY_RESOLVED_BY_VOLUNTEER':
      case 'EMERGENCY_CONTACT_NOTIFIED':
        showNotification(msg.message, msg.ttsText);
        break;
    }
  };

  ws.onclose = () => {
    console.log('WebSocket 断开，3秒后重连...');
    reconnectTimer = setTimeout(() => connectBlindWS(token), 3000);
  };

  ws.onerror = (err) => {
    console.error('WebSocket 错误', err);
  };
}

function startHeartbeat() {
  setInterval(() => {
    if (ws?.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify({ type: 'PING' }));
    }
  }, 30000);
}

function startLocationReport() {
  navigator.geolocation.watchPosition((pos) => {
    if (ws?.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify({
        type: 'LOCATION_UPDATE',
        lat: pos.coords.latitude,
        lng: pos.coords.longitude
      }));
    }
  }, null, { enableHighAccuracy: true });
}
```

### 5.2 志愿者端连接

```javascript
function connectVolunteerWS(token) {
  ws = new WebSocket(`ws://47.114.113.171/ws/volunteer?token=${token}`);

  ws.onopen = () => {
    console.log('志愿者 WebSocket 已连接');
    startLocationReport();
  };

  ws.onmessage = async (event) => {
    const msg = JSON.parse(event.data);
    switch (msg.type) {
      case 'NEW_ORDER':
        const accepted = await showOrderPrompt(msg); // UI 弹窗让志愿者选择
        if (accepted) {
          await fetch(`/api/orders/${msg.orderId}/respond`, {
            method: 'POST',
            headers: {
              'Authorization': `Bearer ${token}`,
              'Content-Type': 'application/json'
            },
            body: JSON.stringify({ action: 'ACCEPT' })
          });
        }
        break;
      case 'EMERGENCY_VOLUNTEER_ALERT':
        showEmergencyAlert(msg); // 紧急弹窗
        break;
      case 'APP_NOTIFICATION':
      case 'ORDER_STATUS_CHANGED':
        showNotification(msg);
        break;
    }
  };

  // ... 同上的 onclose/onerror 处理
}
```

---

## 七、REST 回退接口

当 WebSocket 不可用时，前端可使用以下 REST 接口作为降级方案：

### 获取志愿者位置（盲人端）

```
GET /api/blind/volunteer-location
Authorization: Bearer <token>
```

```json
// 响应
{
  "success": true,
  "data": {
    "orderId": 123,
    "status": "DRIVER_EN_ROUTE",
    "lat": 39.9050,
    "lng": 116.4080,
    "updatedAt": "2026-07-19T12:00:00+08:00"
  }
}
```

仅在订单处于 `PENDING_ACCEPT`、`DRIVER_EN_ROUTE` 或 `DRIVER_ARRIVED` 且位置不超过 30 秒时返回数据；无符合数据时返回 HTTP 200、`success: true`、`data: null`，不得返回旧坐标。`updatedAt` 是带时区 RFC 3339。`需要人工确认`：生产服务的精确时区/小数秒格式以及当前 no-data 是否已经统一为 `data: null`；iOS 在确认前对缺字段、过期、错订单、错状态或非法坐标均静默忽略。

返回的 `lat` / `lng` 为 GCJ-02。此接口只保留 pre-service 回退；`IN_PROGRESS` 使用双向 WebSocket 位置流。

## 八、完成轨迹 REST 契约摘要

`GET /api/orders/{id}/track` 仅允许订单参与者读取，完整 schema 见 `docs/07-api-contract.openapi.yaml`。响应包含：

- `status`：当前订单状态；
- `blindTrack` / `volunteerTrack`：按时间升序的 GCJ-02 `TrackPoint(lat,lng,recordedAt)`；
- `blindStats` / `volunteerStats`：`distanceMeters`、`durationSeconds`、可空 `avgPaceSecPerKm`。

轨迹数组是原始点日志，0、1 或多个点均原样返回，不做点数过滤。某角色少于两个点时，仅该角色统计为 `0 / 0 / null`；iOS 保留单点但不绘制 polyline。接口非 403/404 时 `status` 必有，iOS 据此区分尚未开始、正在采集和历史订单无轨迹；默认只显示至少两个有效盲人点组成的“本次路线”。志愿者轨迹不得用于未获批的异常结论。
