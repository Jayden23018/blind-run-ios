# WebSocket 协议文档

> **版本**: v1.2.0 | **更新**: 2026-05-23
> **导入 Postman**: Postman 支持 WebSocket 请求，可直接使用本文档中的 URL 和消息格式

---

## 一、连接

### 1.1 端点

| 角色 | URL | 认证方式 |
|------|-----|---------|
| 盲人用户 | `ws://{host}:8081/ws/blind?token={jwt}` | URL query param |
| 志愿者 | `ws://{host}:8081/ws/volunteer?token={jwt}` | URL query param |

- **本地开发**: `ws://localhost:8081/ws/blind?token=xxx`
- **生产环境**: `ws://47.114.113.171/ws/blind?token=xxx`（Nginx 代理，端口 80）

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
  "body": "已为您匹配志愿者张三，他正在确认行程，请稍候",
  "ttsText": "已为您匹配志愿者张三，他正在确认行程，请稍候",
  "priority": "NORMAL",
  "timestamp": "2026-05-23T14:05:00"
}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| body | string | 通知文本（显示用） |
| ttsText | string | TTS 朗读文本（盲人用语音播报） |
| priority | string | `"HIGH"` 或 `"NORMAL"` |
| timestamp | string | ISO 格式时间 |

**盲人端常见通知事件**:

| 事件 | body 示例 | priority |
|------|----------|----------|
| 订单被接单 | 已为您匹配志愿者{volunteerName}，他正在确认行程，请稍候 | NORMAL |
| 志愿者出发 | 志愿者{volunteerName}已出发，正在赶往您的位置 | NORMAL |
| 志愿者到达 | 志愿者{volunteerName}已到达附近 | HIGH |
| 订单完成 | 订单已完成 | NORMAL |
| 重新匹配 | 志愿者已取消，正在重新匹配 | NORMAL |
| 暂无志愿者 | 暂时没有可用志愿者，仍在等待 | NORMAL |
| 邻近感知 | 志愿者距您约100米 | NORMAL |
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
  "ttsText": "志愿者张三已出发，正在赶往您的位置",
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
PENDING_MATCH → PENDING_ACCEPT → IN_PROGRESS → DRIVER_EN_ROUTE → DRIVER_ARRIVED → COMPLETED
      ↓              ↓                ↓                ↓                 ↓
  CANCELLED      REMATCHING       CANCELLED       REMATCHING        REMATCHING

NO_VOLUNTEER（无可用志愿者）
```

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
- 位置同时写入 Redis（30s TTL）和 MySQL
- 建议每 5~10 秒上报一次

### 3.2 服务器 → 客户端

#### NEW_ORDER — 新订单派单通知（核心消息）

串行派单系统向志愿者推送新订单，志愿者必须在 `dispatchTimeoutSeconds` 秒内响应。

```json
{
  "type": "NEW_ORDER",
  "orderId": 123,
  "startAddress": "朝阳公园南门",
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
| distanceKm | number | 是 | 志愿者到起点的距离（公里） |
| plannedStart | string | 是 | 计划开始时间（ISO 格式） |
| plannedEnd | string | 是 | 计划结束时间（ISO 格式） |
| dispatchTimeoutSeconds | number | 是 | 响应超时时间（秒），默认 30 |
| priority | string | 是 | 固定 `"HIGH"` |
| pacePreference | string | 否 | 配速偏好（如 `MODERATE`） |
| hasGuideDog | boolean | 否 | 盲人是否携带导盲犬 |
| specialNotes | string | 否 | 盲人备注 |

**响应方式**: 收到后必须通过 REST API 响应，不是通过 WebSocket 回复。

```
POST /api/orders/{orderId}/respond
Authorization: Bearer <token>
Content-Type: application/json

// 接受
{ "action": "ACCEPT" }

// 拒绝
{ "action": "DECLINE" }
```

**超时未响应**: 系统自动视为拒绝，派单给下一位志愿者。

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
| 培训完成 | 恭喜您完成所有必修课程，现在可以接单了 | HIGH |
| 订单超时 | 订单已超过结束时间1小时 | HIGH |
| 邻近感知 | 您已到达盲人附近 | NORMAL |

#### ORDER_STATUS_CHANGED — 订单状态变更

与盲人端格式相同。志愿者端会收到订单生命周期中的状态变更通知。

#### EMERGENCY_VOLUNTEER_ALERT — 紧急求助告警

盲人触发紧急求助后，关联的志愿者会收到此消息。

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

## 四、消息类型速查表

### 盲人端（`/ws/blind`）

| 方向 | type | 触发场景 | priority |
|------|------|---------|----------|
| 发送 | `LOCATION_UPDATE` | 定时上报位置（5~10s） | — |
| 发送 | `PING` | 心跳（30s） | — |
| 接收 | `PONG` | 心跳响应 | — |
| 接收 | `VOLUNTEER_LOCATION_UPDATE` | 志愿者位置实时转发 | — |
| 接收 | `APP_NOTIFICATION` | 模板通知 | HIGH/NORMAL |
| 接收 | `ORDER_STATUS_CHANGED` | 订单状态变更 | HIGH/NORMAL |
| 接收 | `EMERGENCY_RESOLVED_BY_VOLUNTEER` | 志愿者确认紧急事件 | HIGH |
| 接收 | `EMERGENCY_CONTACT_NOTIFIED` | 紧急联系人已通知 | HIGH |

### 志愿者端（`/ws/volunteer`）

| 方向 | type | 触发场景 | priority |
|------|------|---------|----------|
| 发送 | `LOCATION_UPDATE` | 定时上报位置（5~10s） | — |
| 接收 | `NEW_ORDER` | 串行派单推送 | HIGH |
| 接收 | `APP_NOTIFICATION` | 模板通知 | HIGH/NORMAL |
| 接收 | `ORDER_STATUS_CHANGED` | 订单状态变更 | HIGH/NORMAL |
| 接收 | `EMERGENCY_VOLUNTEER_ALERT` | 紧急求助告警 | HIGH |

---

## 五、前端对接 JavaScript 示例

### 5.1 盲人端连接

```javascript
let ws = null;
let reconnectTimer = null;

function connectBlindWS(token) {
  ws = new WebSocket(`ws://localhost:8081/ws/blind?token=${token}`);

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
  ws = new WebSocket(`ws://localhost:8081/ws/volunteer?token=${token}`);

  ws.onopen = () => {
    console.log('志愿者 WebSocket 已连接');
    startLocationReport();
  };

  ws.onmessage = async (event) => {
    const msg = JSON.parse(event.data);
    switch (msg.type) {
      case 'NEW_ORDER':
        const accepted = await showOrderPrompt(msg); // UI 弹窗让志愿者选择
        await fetch(`/api/orders/${msg.orderId}/respond`, {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${token}`,
            'Content-Type': 'application/json'
          },
          body: JSON.stringify({ action: accepted ? 'ACCEPT' : 'DECLINE' })
        });
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

## 六、REST 回退接口

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
    "lat": 39.9050,
    "lng": 116.4080,
    "updatedAt": "2026-05-23T14:05:00"
  }
}
```

仅在订单处于 `DRIVER_EN_ROUTE` 或 `DRIVER_ARRIVED` 状态时返回数据。
