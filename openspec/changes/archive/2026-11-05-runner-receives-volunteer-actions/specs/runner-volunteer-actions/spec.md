## Purpose

跑者端接收陪跑员在汇合阶段发来的动作（响铃、迟到提醒、快捷消息），并让跑者提前写下引导偏好与出发前留言。

## ADDED Requirements

### Requirement: 响铃循环到 until
跑者在 App 前台收到 `APP_NOTIFICATION`（`eventType=RUNNER_RING`）时，App SHALL 朗读 `ttsText`（缺失时用 `body`），并以播放器最大音量循环播放专用提示音，直到信封 `until` 所指的时刻（按服务端时钟换算成时长，上限 30 秒）。

#### Scenario: 正常响铃
- **WHEN** 跑者收到带 `until`（10 秒后）的 `RUNNER_RING`
- **THEN** 手机朗读「你的陪跑员到了，正在找你」并循环响铃，到 `until` 自动停止

#### Scenario: 缺 until 或已过期
- **WHEN** `RUNNER_RING` 没有可解析的 `until`，或 `until` 不晚于 `timestamp`
- **THEN** 不响铃，只按普通通知朗读一次

#### Scenario: 同一条重复收到
- **WHEN** 同一 `messageId` 的 `RUNNER_RING` 再次到达
- **THEN** 不重新开始响铃、不再朗读

#### Scenario: 响铃期间来了新的一次
- **WHEN** 响铃中收到另一个 `messageId` 的 `RUNNER_RING`
- **THEN** 按新的 `until` 重新计时

### Requirement: 任意操作即停
响铃期间 App SHALL 盖一层整屏的「停止响铃」，点击任意位置、VoiceOver 双击、magic tap 或返回手势都 MUST 立即停止声音并移除遮罩；遮罩期间背后的页面对读屏隐藏，magic tap MUST NOT 触发求助。

#### Scenario: 读屏用户 magic tap
- **WHEN** 响铃中跑者做两指双击
- **THEN** 响铃停止，求助确认不弹出

### Requirement: 陪跑员迟到与快捷消息朗读
`VOLUNTEER_LATE`、`VOLUNTEER_BACK_ON_TIME` 与任何 `QUICK_MESSAGE_*`（包括客户端不认识的新预设）SHALL 作为高优先级前台通知朗读 `ttsText`，不得被生命周期去重抑制，未知取值不得导致整条推送丢失。

#### Scenario: 未知快捷消息
- **WHEN** 收到 `eventType=QUICK_MESSAGE_AT_GATE_B`
- **THEN** 照常朗读其 `ttsText`

### Requirement: 引导偏好录入
跑者资料页 SHALL 提供「给陪跑员的引导偏好」自由文本，按 UTF-16 计不超过 80；保存时去首尾空白，空串表示清空；页面 MUST 说明陪跑员接单后才看得到。

#### Scenario: 超长
- **WHEN** 跑者输入超过 80 个字符后点保存
- **THEN** 不提交，屏幕与语音都说明上限和当前字数

### Requirement: 出发前留言
在 `SCHEDULED_CONFIRMED` / `PENDING_ACCEPT` / `DRIVER_EN_ROUTE` / `DRIVER_ARRIVED` 这四态，订单页 SHALL 提供「给陪跑员留言」入口，保存走 `PUT /api/orders/{id}/runner-message`（≤40，空串 = 清空），其余状态不显示该入口。

#### Scenario: 保存成功
- **WHEN** 跑者在 `DRIVER_EN_ROUTE` 写下「我穿红色外套」并保存
- **THEN** 订单页显示并朗读「留言已发给陪跑员」，行内显示留言原文

#### Scenario: 非可写状态
- **WHEN** 订单处于 `PENDING_MATCH` 或 `IN_PROGRESS`
- **THEN** 不显示留言入口
