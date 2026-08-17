# WebSocket 协议文档

> **版本**: v1.3.0 | **更新**: 2026-07-19
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
| 心跳超时 | 建议每 30s 发送 PING（仅盲人端支持） |

### 1.4 断线重连

建议前端实现自动重连机制：
- 重连间隔：3 秒（建议）
- 指数退避：3s → 6s → 12s → 最大 30s
- 重连后重新发送位置上报

---

## 二、盲人用户 WebSocket (`/ws/blind`)

### 2.1 客户端 → 服务器

#### LOCATION_UPDATE — 位置上报

前端定时（建议 5~10 秒）上报盲人用户 GPS 位置。

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

当订单处于 `DRIVER_EN_ROUTE` 或 `DRIVER_ARRIVED` 状态时，志愿者每次上报位置都会转发给盲人。

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
  "eventId": 789,
  "title": "订单提醒",
  "body": "已为您匹配志愿者张三，他正在确认行程，请稍候",
  "ttsText": "已为您匹配志愿者张三，他正在确认行程，请稍候",
  "priority": "NORMAL",
  "timestamp": "2026-05-23T14:05:00"
}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| eventId | number | 可选稳定事件 ID；存在时用于前台通知去重 |
| title | string | 可选安全展示标题 |
| body | string | 通知文本（显示用） |
| ttsText | string | TTS 朗读文本建议；订单生命周期播报以 iOS 本地订单详情文案为准，不直接朗读生命周期模板 |
| priority | string | `"HIGH"` 或 `"NORMAL"` |
| timestamp | string | ISO 格式时间 |

当前 iOS 协调器仅接受上述平铺 `APP_NOTIFICATION`。`priority` 仅允许 `HIGH` / `NORMAL`，缺省按 `NORMAL`；`timestamp` 使用带时区的 RFC 3339。`需要人工确认`：生产服务是否仍可能发送 `NOTIFICATION` + 嵌套 `data`、是否始终提供 `eventId`，以及未知优先级的服务端约束。

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
  "orderId": 123,
  "fromStatus": "IN_PROGRESS",
  "toStatus": "DRIVER_EN_ROUTE",
  "message": "志愿者已出发",
  "ttsText": "志愿者已出发，正在前往出发地点",
  "priority": "NORMAL",
  "timestamp": "2026-05-23T14:10:00"
}
```

| 字段 | 类型 | 说明 |
|------|------|------|
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

#### BLIND_LOCATION_UPDATE — 盲人位置转发（契约预留）

后端将关联订单中盲人上报的位置转发给志愿者；本变更只负责类型化路由，不展示对方 marker、不启动五秒服务轨迹采集。

```json
{
  "type": "BLIND_LOCATION_UPDATE",
  "orderId": 123,
  "lat": 39.9042,
  "lng": 116.4074,
  "timestamp": 1784433600000
}
```

`orderId` 为关联订单，`lat` / `lng` 必须位于合法范围，`timestamp` 为 Unix 毫秒。`需要人工确认`：生产 WebSocket 是否已启用该平铺 envelope、适用订单状态及坐标系归一化责任；确认前 iOS 仅内存路由，不增加 peer UI。

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

与盲人端格式相同。志愿者端会收到订单生命周期中的状态变更通知。

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

### SEPARATION_ALERT — 分离提醒（契约预留）

```json
{
  "type": "SEPARATION_ALERT",
  "eventId": 991,
  "orderId": 123,
  "distanceMeters": 120,
  "message": "请注意与同行者的距离",
  "ttsText": "请注意与同行者的距离",
  "priority": "HIGH",
  "timestamp": "2026-07-19T12:00:00+08:00"
}
```

`eventId`、`orderId`、`message` 为必填；`priority` 固定 `HIGH`。两个不同 `eventId` 即使文案相同也必须分别路由和播报。`需要人工确认`：生产服务的最终 type 名称、距离字段、阈值责任和双角色投递范围；本变更不实现分离判定或功能动作。

### App 生命周期协调规则

- `AppState` 只持有一个 `AppRealtimeCoordinator`，对当前角色 socket 恰好订阅一次；退出、角色/token 或服务替换时清理旧用户内存事件。
- `ORDER_STATUS_CHANGED` 只触发按 `orderId` 合并的 REST 详情刷新，不能用局部 WebSocket payload 构造权威订单。
- `NEW_ORDER` 保留至接受、拒绝、超时、后端状态使其失效或角色改变，页面切换不能丢失。
- 两个方向的位置消息按订单和接收角色校验；错误订单或非法坐标静默丢弃，日志、可见 UI 和无障碍文本不得输出原始坐标。
- `HIGH` 前台通知抢占 `NORMAL`。非安全事件按 `eventId` 或类型/规范化文案/时间去重；不同安全 `eventId` 不合并。
- 重连后协调器请求活动订单与角色摘要刷新，并通知依赖功能恢复各自节奏。传输层继续保持 500 ms 最小发送间隔、3/6/12/30 秒退避、未知消息容忍和 30 秒心跳。

## 五、消息类型速查表

### 盲人端（`/ws/blind`）

| 方向 | type | 触发场景 | priority |
|------|------|---------|----------|
| 发送 | `LOCATION_UPDATE` | 定时上报位置（5~10s） | — |
| 发送 | `PING` | 心跳（30s） | — |
| 接收 | `PONG` | 心跳响应 | — |
| 接收 | `VOLUNTEER_LOCATION_UPDATE` | 志愿者位置实时转发 | — |
| 接收 | `SEPARATION_ALERT` | 分离提醒契约预留 | HIGH |
| 接收 | `APP_NOTIFICATION` | 模板通知 | HIGH/NORMAL |
| 接收 | `ORDER_STATUS_CHANGED` | 订单状态变更 | HIGH/NORMAL |
| 接收 | `EMERGENCY_RESOLVED_BY_VOLUNTEER` | 志愿者确认紧急事件 | HIGH |
| 接收 | `EMERGENCY_CONTACT_NOTIFIED` | 紧急联系人已通知 | HIGH |

### 志愿者端（`/ws/volunteer`）

| 方向 | type | 触发场景 | priority |
|------|------|---------|----------|
| 发送 | `LOCATION_UPDATE` | 定时上报位置（5~10s） | — |
| 接收 | `NEW_ORDER` | 串行派单推送 | HIGH |
| 接收 | `BLIND_LOCATION_UPDATE` | 盲人位置转发契约预留 | — |
| 接收 | `SEPARATION_ALERT` | 分离提醒契约预留 | HIGH |
| 接收 | `APP_NOTIFICATION` | 模板通知 | HIGH/NORMAL |
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
      case 'APP_NOTIFICATION':
        showNotification(msg.body, msg.ttsText);
        if (msg.ttsText) speakTTS(msg.ttsText); // 语音播报
        break;
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
