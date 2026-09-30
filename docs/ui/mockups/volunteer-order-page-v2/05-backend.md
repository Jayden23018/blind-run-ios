# 05 · 后端（Spring Boot）

**先读现有代码。** 现有系统已有订单、WebSocket GPS 追踪、紧急求助、志愿者认证。下面的状态名、字段名、接口路径都是建议，已有同义实现的一律复用，并在 PR 里写明映射。现有 116 个测试必须保持通过。

## 一、状态机（与 v3 一致，只是明确化）

```
INVITED ──accept──▶ AGREED ──depart──▶ DEPARTED ──arrive──▶ ARRIVED ──startRun──▶ RUNNING ──endRun──▶ COMPLETED
   │                  │                   │                    │
   ├─decline─▶ DECLINED                   │                    └─endWait(≥15 分钟)─▶ WAIT_ENDED
   ├─timeout─▶ EXPIRED                    │
   ├─taken───▶ TAKEN                      │
   │          AGREED/DEPARTED ──volunteerCancel──▶ VOLUNTEER_CANCELLED
   │          AGREED/DEPARTED/ARRIVED ──runnerCancel──▶ RUNNER_CANCELLED
```

- `DEPARTED` 下的"快迟到"不是独立状态，是 `eta.lateMinutes > 3` 的派生属性
- `AGREED` 下的"前一晚 / 出发前 30 分钟"也不是独立状态，由客户端按 `primaryActionUnlockAt` 判断
- `startRun` 双方都能触发，先到的生效，后到的返回 200 + 当前状态（幂等），**不能**返回错误（v3 不变）
- 所有状态迁移接口必须幂等，并用乐观锁（`version` 字段）防止并发；`accept` 冲突时返回 409 + `TAKEN`（v3 B9）

## 二、新增或调整的能力

### 1. 订单页聚合视图

新增 `GET /api/volunteer/orders/{orderId}/view`，一次返回订单页需要的全部数据（DTO 见 06）。按状态裁剪字段：

| 字段 | INVITED | AGREED 及以后 |
|---|---|---|
| 跑者姓氏、视力情况、引导工具、偏好原话 | ✓ | ✓ |
| 跑者全名、电话 | ✗ | ✓ |
| 跑者给陪跑员的留言 | ✗ | ✓ |
| 衣着 | ✗ | 跑者填写后 ✓ |
| 跑者位置相关（presence、汇合方位） | ✗ | 仅 DEPARTED / ARRIVED，且跑者开启了位置共享 |

### 2. 时间计算

对每个订单保存并随出发地 / 交通方式变化重算：

- `travelMinutes`：按陪跑员出发地 + 常用交通方式估算（沿用现有实现；没有就先用直线距离 × 系数：骑车 1.4 倍直线距离、15 km/h）
- `suggestedDepartAt = startAt − travelMinutes − 5 分钟缓冲`（示例：7:00 − 20 − 5 = 6:35）
- `departReminderAt = suggestedDepartAt − 5 分钟`（v3：建议出发前 5 分钟，时间敏感推送）
- `primaryActionUnlockAt = suggestedDepartAt − 30 分钟`

### 3. 出发中的 ETA

陪跑员在 `DEPARTED` 状态下通过现有 WebSocket 上报位置（建议 10–15 秒一次）。服务端每次收到位置时：

- `remainingMinutes`：按剩余距离和交通方式速度估算；有真实速度（最近 1 分钟平均）时用真实速度，并限制在理论速度的 0.5–1.5 倍之间
- `arriveAt = now + remainingMinutes`
- `deltaVsStartMinutes = arriveAt − startAt`（负数为提前）
- `progress = 1 − 剩余距离 / 出发时距离`，限制在 0.1–0.85 之间
- **推送节流**：`remainingMinutes` 变化 ≥1 分钟时，才通过 WebSocket 发送 `order.eta_updated` 并更新实时活动
- **晚到通知**（v3 D2）：`deltaVsStartMinutes > 3` 时自动通知跑者端；之后变化超过 3 分钟才再通知一次；追回到 ≤3 分钟时发送一次"恢复准时"事件

### 4. 跑者在场状态

`runnerPresence.nearMeetingPoint = 跑者位置距集合点 ≤ 100 米，且位置更新时间在 2 分钟内`。仅当跑者开启位置共享时计算；未开启时返回 `sharingEnabled = false`，客户端隐藏整个胶囊。

### 5. 汇合距离档位

`ARRIVED` 状态下，服务端把跑者的位置（带精度）经 WebSocket `meet.runner_location` 转发给陪跑员端，频率上限每 3 秒一次。**方位由客户端计算**（需要陪跑员自己的朝向）。距离档位两端都能算，规则统一如下，以服务端返回的为准：

```
d = 两点距离, e = max(跑者精度, 陪跑员精度)
d + e ≤ 10     → WITHIN_10
d + e ≤ 50     → WITHIN_50
d + e ≤ 100    → WITHIN_100
d > 100        → FAR（同时返回公里数，保留 1 位小数）
任一位置超过 60 秒未更新，或 e > 100 → UNKNOWN
```

### 6. 让跑者手机响铃（新增）

`POST /api/volunteer/orders/{orderId}/ring-runner`

- 只允许在 `ARRIVED` 或 `RUNNING` 状态调用（v2），只能由该订单的陪跑员调用
- 限流：每次响铃持续 10 秒；两次调用之间至少间隔 10 秒；每个订单最多 20 次
- 服务端经跑者端 WebSocket 发送 `runner.ring`，跑者端离线时退化为时间敏感推送（声音 + 通知文字"你的陪跑员到了，正在找你"）
- 返回 `ringingUntil`
- **跑者端需要实现**：收到后以最大媒体音量播放提示音，并用 TTS 播报「你的陪跑员到了，正在找你」；循环 10 秒；跑者端任意操作即停止

### 7. 快捷回复

`POST /api/volunteer/orders/{orderId}/quick-reply`，`type ∈ {ALMOST_THERE, WAIT_5_MIN}`。对应文案「我快到了」「再等我 5 分钟」（v3 的「我到入口了」已废弃）。跑者端用 TTS 播报。同一 type 60 秒内重复调用返回 429。也需要支持从实时活动的 App Intent 调用（使用同一个接口和鉴权）。

### 8. 跑者的偏好原话与留言（新增，跑者端配合）

- 跑者资料新增 `guidePreferenceText`（≤80 字）。为空时，陪跑员端回退到 v3 的结构化引导习惯
- 订单新增 `runnerMessageToVolunteer`（≤40 字），`AGREED` 之后、`RUNNING` 之前跑者可写一次、可修改
- 完成后的跑者留言 `runnerNote` 沿用 v3；新增陪跑员回复 `volunteerReply`（≤60 字，只能回复一次）
- 所有文本都要经过现有的敏感词过滤

### 9. 集合点地标（新增，后台配置）

集合点实体新增 `landmark`（≤20 字，如「石牌左边的空地」），在组织后台维护。无集合点实体、只有自由文本地址的订单，`landmark` 返回 null。

### 10. 一起跑过的次数

`runCountTogether`：该陪跑员与该跑者之间状态为 `COMPLETED` 的订单数（不含当前订单）。完成页显示"第 N 次"时，N = 这个数 + 1。

### 11. 实时活动推送

- `POST /api/devices/live-activity-token`：`{orderId, pushToken}`，陪跑员开启实时活动后上传
- 使用 APNs token-based 认证，`apns-push-type: liveactivity`，`apns-topic: {bundleId}.push-type.liveactivity`
- 在以下情况发送 `update`：状态变化、ETA 变化 ≥1 分钟、晚到状态变化、`runnerNearMeetingPoint` 变化、汇合距离档位变化
- 完成 / 取消 / 结束等待时发送 `end`
- ContentState 的 JSON 字段必须和 04 里的 Swift 结构逐字段对应（camelCase，日期用秒级 Unix 时间戳）

## 三、推送与提示级别（v3 矩阵不变，这里只列本期涉及的）

| 事件 | 通道 | 级别 |
|---|---|---|
| 出发提醒 | APNs | 时间敏感，建议出发前 5 分钟 |
| 进入集合点 100 米 | APNs + 页面 | 普通，询问「到了吗」，不自动迁移状态 |
| 跑者在陪跑员出发后取消 | APNs + WebSocket | 时间敏感 |
| 跑者留言（约好后） | WebSocket；App 不在前台时普通 APNs | 普通，锁屏文案不含留言内容 |
| 响铃（发往跑者端） | WebSocket，离线时 APNs | 时间敏感 |

## 四、隐私

- 接单前不下发全名、电话、留言、位置（v3）
- 跑者位置只在 `DEPARTED` 和 `ARRIVED` 状态、且跑者开启共享时转发给该订单的陪跑员；订单进入终止状态后立即停止转发
- 锁屏推送和实时活动只使用姓氏
- 不向陪跑员展示跑者的爽约记录或取消原因（v3）

## 五、v2 新增：跑步中

节奏信号、暂停 / 继续、疑似走散、跑者电量、折返点、紧急求助在跑步中的要求，见 `08-running.md` 第七节。
