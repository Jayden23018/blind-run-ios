## Why

陪跑员订单页 v2 已经能「让 TA 的手机响起来」、发快捷消息，后端也会推迟到提醒（`RUNNER_RING` / `QUICK_MESSAGE_*` / `VOLUNTEER_LATE` / `VOLUNTEER_BACK_ON_TIME`，迁移 `202609252356`–`202609260124`）。跑者端目前只有通用横幅：响铃不会响，陪跑员靠声音找人的前提不成立；引导偏好和出发前留言两个字段后端已上线、陪跑员端已展示，但跑者端没有录入入口（issue #214）。

## What Changes

- 收到 `RUNNER_RING`：朗读 `ttsText`，随后以 App 能给的最大音量（播放器音量 1、`.playback` 分类不受静音拨杆影响）循环播放专用提示音，直到信封里的 `until`；屏幕盖一层整屏「停止响铃」，任意点击 / 双击 / magic tap / 返回手势都立即停。同一条消息重复收到不重响；缺 `until` 或已过期时不响，只朗读。
- `VOLUNTEER_LATE` / `VOLUNTEER_BACK_ON_TIME` / `QUICK_MESSAGE_*`（含后端以后新增的未知 `QUICK_MESSAGE_*`）：照通用通道朗读 `ttsText`，本次用测试钉住，不新增分支。
- 资料页新增「给陪跑员的引导偏好」自由文本（≤80，按 UTF-16 计），写明「陪跑员接单后才看得到」；清空传空串。
- 订单页在 `SCHEDULED_CONFIRMED` / `PENDING_ACCEPT` / `DRIVER_EN_ROUTE` / `DRIVER_ARRIVED` 给出「给陪跑员留言」入口，调 `PUT /api/orders/{id}/runner-message`（≤40）。

## Capabilities

### New Capabilities
- `runner-volunteer-actions`: 跑者端如何接收陪跑员的响铃 / 迟到 / 快捷消息，以及如何录入引导偏好与出发前留言。

### Modified Capabilities

## Impact

- 代码：`blindRun/BlindRunner/**`（响铃控制器与遮罩、留言入口）、`AppRealtimeCoordinator` 的 `APP_NOTIFICATION` 路由、`WSAppNotification`（多解一个 `until`）、资料页与 `BlindProfileUpdateRequest`、`OrderServing` 加一个方法。
- 契约：只读后端 `api_spec.yaml`（`ring-runner` / `runner-message` / `BlindProfileUpdateRequest`）与 `websocket-protocol.md` §2.2，不改。
- 不在本变更：APNs 推送与锁屏（#213）、陪跑员端页面（#218）、系统音量的强制拉满（公开 API 做不到）。
