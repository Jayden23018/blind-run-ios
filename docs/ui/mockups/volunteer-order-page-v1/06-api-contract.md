# 06 · 接口契约

两端以本文件对齐。路径和字段名为建议，后端改名后需同步更新本文件。时间一律 ISO 8601 带时区（`+08:00`），实时活动 ContentState 除外（见 04、05）。

## REST

| 方法 | 路径 | 说明 | 状态要求 |
|---|---|---|---|
| GET | `/api/volunteer/orders/{id}/view` | 订单页聚合视图 | 任意 |
| POST | `/api/volunteer/orders/{id}/accept` | 接下 | INVITED；冲突 409 |
| POST | `/api/volunteer/orders/{id}/decline` | 这次去不了（5 秒内可撤销，沿用 v3） | INVITED |
| POST | `/api/volunteer/orders/{id}/depart` | 我出发了 | AGREED |
| POST | `/api/volunteer/orders/{id}/arrive` | 我已到达集合点 | DEPARTED |
| POST | `/api/volunteer/orders/{id}/start-run` | 开始跑步（幂等） | ARRIVED |
| POST | `/api/volunteer/orders/{id}/end-wait` | 结束等待 | ARRIVED 且已等待 ≥15 分钟 |
| POST | `/api/volunteer/orders/{id}/cancel` | 陪跑员取消（沿用 v3 D1） | AGREED / DEPARTED |
| POST | `/api/volunteer/orders/{id}/quick-reply` | `{ "type": "ALMOST_THERE" \| "WAIT_5_MIN" }` | DEPARTED / ARRIVED |
| POST | `/api/volunteer/orders/{id}/ring-runner` | 响铃，返回 `{ "ringingUntil": "…" }` | ARRIVED |
| POST | `/api/volunteer/orders/{id}/reply` | `{ "text": "…" }` 回复跑者留言，≤60 字，一次 | COMPLETED |
| POST | `/api/devices/live-activity-token` | `{ "orderId", "pushToken" }` | DEPARTED 起 |
| PUT | `/api/runner/profile/guide-preference` | 跑者端：`{ "text": "…" }` ≤80 字 | — |
| PUT | `/api/runner/orders/{id}/message` | 跑者端：`{ "text": "…" }` ≤40 字 | AGREED 至 ARRIVED |

所有状态迁移接口的成功响应都返回最新的 `OrderView`，客户端直接用它刷新页面。

错误码：`409 ORDER_TAKEN`、`409 INVALID_STATE`（附带当前 `state`）、`429 RATE_LIMITED`（附带 `retryAfterSeconds`）、`403 NOT_ORDER_OWNER`。

## OrderView

```json
{
  "orderId": "ord_20260919_0700_001",
  "state": "DEPARTED",
  "version": 7,
  "startAt": "2026-09-19T07:00:00+08:00",
  "suggestedDepartAt": "2026-09-19T06:35:00+08:00",
  "departReminderAt": "2026-09-19T06:30:00+08:00",
  "primaryActionUnlockAt": "2026-09-19T06:05:00+08:00",
  "travelMode": "BIKE",
  "travelMinutes": 20,
  "distanceKmFromVolunteer": 3.2,
  "targetDistanceKm": 5,
  "targetPace": "7'00\"",

  "invite": {
    "replyDeadline": "2026-09-18T22:00:00+08:00",
    "reasonText": "在你周六早上的空闲时间里"
  },

  "runner": {
    "surname": "李",
    "displayName": "李明",
    "honorific": "李先生",
    "phone": "138****0000",
    "visionDescription": "全盲",
    "guideTool": "引导绳",
    "guidePreferenceText": "我习惯你在我左边。过台阶和转弯前，提前说一声就好。",
    "structuredGuideHabits": ["陪跑员在左侧", "过台阶提前说一声"],
    "messageToVolunteer": "明天见，谢谢你陪我跑！",
    "runCountTogether": 3
  },

  "meetingPoint": {
    "name": "深圳湾公园 3 号入口",
    "shortName": "3 号入口",
    "landmark": "石牌左边的空地",
    "lat": 22.5000,
    "lng": 113.9500
  },

  "eta": {
    "remainingMinutes": 8,
    "arriveAt": "2026-09-19T06:57:00+08:00",
    "deltaVsStartMinutes": -3,
    "late": false,
    "progress": 0.68,
    "lateNotifiedRunner": false
  },

  "runnerPresence": {
    "sharingEnabled": true,
    "nearMeetingPoint": true
  },

  "meet": {
    "arrivedAt": null,
    "distanceBucket": null,
    "farDistanceKm": null
  },

  "clothing": [
    { "part": "TOP", "label": "深蓝上衣", "colorHex": "#1E2A55" },
    { "part": "HAT", "label": "白色帽子", "colorHex": "#FFFFFF" }
  ],

  "completion": null
}
```

字段规则：
- `INVITED` 时 `runner.displayName`、`phone`、`messageToVolunteer` 为 null，`honorific` 用于显示「李先生」
- `invite` 只在 `INVITED` 时非空；`reasonText` 由后端生成，**只能描述匹配原因**（空闲时间、距离、一起跑过），不能出现催促或"没人接"一类文案
- `eta` 只在 `DEPARTED` 时非空；`meet` 只在 `ARRIVED` 时非空
- `runnerPresence.sharingEnabled == false` 时 `nearMeetingPoint` 为 null

`COMPLETED` 时的 `completion`：

```json
{
  "distanceKm": 5.12,
  "durationSeconds": 2360,
  "serviceHours": 0.7,
  "certificationStatus": "PENDING",
  "runnerNote": "今天的节奏很舒服，台阶提醒得特别及时。下次还想和你一起跑。",
  "volunteerReply": null,
  "newBadge": null,
  "runIndexTogether": 4
}
```

`newBadge` 只在本次真正解锁新奖章时返回 `{ "id", "name" }`。

## WebSocket 事件（陪跑员端订阅 `order.{orderId}`）

| 事件 | 载荷 | 说明 |
|---|---|---|
| `order.state_changed` | 完整 `OrderView` | 任意状态迁移，包括对方触发的 |
| `order.eta_updated` | `eta` 对象 | 剩余分钟变化 ≥1 时 |
| `runner.presence_updated` | `runnerPresence` 对象 | 在场状态变化时 |
| `meet.runner_location` | `{ "lat", "lng", "accuracyM", "at" }` | ARRIVED 时，每 3 秒最多一次 |
| `meet.distance_bucket` | `{ "distanceBucket", "farDistanceKm" }` | 档位变化时 |
| `runner.message_updated` | `{ "messageToVolunteer" }` | 跑者修改留言 |

陪跑员端上行（沿用现有 GPS 通道）：`volunteer.location { lat, lng, accuracyM, speedMps, at }`，DEPARTED 和 ARRIVED 状态下每 10–15 秒一次。

## 跑者端需要订阅（跨端）

| 事件 | 跑者端行为 |
|---|---|
| `runner.ring` `{ "until" }` | 最大媒体音量播放提示音 + TTS「你的陪跑员到了，正在找你」，循环到 `until` |
| `volunteer.quick_reply` `{ "type" }` | TTS 播报「张伟说：我快到了」或「张伟说：再等我 5 分钟」 |
| `volunteer.late` `{ "lateMinutes" }` | 沿用 v3 D2 |
