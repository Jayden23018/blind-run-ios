# running-rhythm-and-help Specification

## Purpose
TBD - created by archiving change add-running-rhythm-pause-and-help-panel. Update Purpose after archive.
## Requirements
### Requirement: 耳机语音播报开关
跑步页 SHALL 提供默认关闭的「耳机语音播报」开关，状态存本地、跨订单保留；开启时每满 1 公里播报「N 公里，用时 X 分 Y 秒」。跑步页 MUST NOT 播报任何节奏信号。

#### Scenario: 默认关
- **WHEN** 首次进入跑步页
- **THEN** 开关为关，跨过 1 公里不播报

#### Scenario: 开启后满 1 公里
- **WHEN** 开关为开且里程跨过 1 公里
- **THEN** 播报「1 公里，用时 X 分 Y 秒」，且不播报任何节奏相关的话

### Requirement: 提示条只显示一条
跑步页 SHALL 在头卡下方显示至多一条提示，与 `volunteer-running-page` 的提示条共用一个队列：跑者求助已确认 > 走散（最近一次 `ESCORT_DISTANCE_ALERT` 后 60 秒内）> 收不到跑者位置 > 跑者电量低（`run.runnerBatteryLow`）> 本机定位精度差于 50 米持续 20 秒。走散提示 MUST NOT 带响铃按钮。

#### Scenario: 走散与电量低同时成立
- **WHEN** 60 秒内收到过走散告警且跑者电量低
- **THEN** 只显示走散提示

### Requirement: 暂停与继续
陪跑员 SHALL 能从求助面板暂停计时（`POST /api/orders/{id}/pause`）；`run.paused=true` 时头卡底色 SHALL 换成 `statePaused`、小标题为「已暂停 · 计时停在 mm:ss」（取 `run.elapsedSeconds`），底部栏 SHALL 出现「继续陪跑」黄色主按钮（`/resume`），它是本屏唯一的黄色按钮，长按结束仍在它下方。

#### Scenario: 暂停中
- **WHEN** 订单详情 `run.paused=true`、`run.elapsedSeconds=1112`
- **THEN** 头卡小标题为「已暂停 · 计时停在 18:32」，底部出现「继续陪跑」

### Requirement: 跑步中求助面板
`IN_PROGRESS` 时陪跑员右上角「求助」SHALL 打开求助面板而非直接发求助。面板包含：暂停（已暂停时隐藏）、让跑者手机响（「让{名}的手机响起来」，调 `POST /api/orders/{id}/ring-runner`，在响应的 `ringingUntil` 之前显示「正在响铃…」且不可点）、联系客服（一键提交带订单号的工单，成功后显示「客服会尽快联系你」）、长按 3 秒紧急求助（走现有云端链路）。轻点或 VoiceOver 双击紧急按钮 MUST 弹出 `AGENTS.md` §6 锁定文案的确认框；紧急按钮副标题 MUST NOT 声称任何人已收到。响铃的结果 SHALL 显示在跑步页：`delivered=false` 时显示并朗读「对方可能没收到，可以打电话。」，429 时说明多少秒后再试；该回执 MUST 在订单状态变化时清除。

#### Scenario: 读屏双击紧急按钮
- **WHEN** VoiceOver 用户双击「长按 3 秒，紧急求助」
- **THEN** 弹出「是否确认进入求助状态？…」确认框，确认后才发

#### Scenario: 长按满 3 秒
- **WHEN** 陪跑员按住紧急按钮满 3 秒
- **THEN** 面板关闭，走现有云端求助，结果显示在跑步页求助结果区

#### Scenario: 走散时让跑者手机响
- **WHEN** 陪跑员在求助面板按「让李的手机响起来」
- **THEN** 面板关闭并调 `ring-runner`；成功时朗读「李的手机正在响」，再次打开面板时那一行在 `ringingUntil` 之前显示「正在响铃…」且不可点

#### Scenario: 汇合期的回执不带进跑步中
- **WHEN** 汇合期响铃回执为「对方可能没收到，可以打电话。」，随后订单转 `IN_PROGRESS`
- **THEN** 跑步页不显示这句回执

### Requirement: 跑者电量随位置上报
跑者角色的 `LOCATION_UPDATE` SHALL 附带 `batteryLevel`（0–1）；读不到电量时 MUST 不传该键；陪跑员角色 MUST NOT 附带。

#### Scenario: 电量未知
- **WHEN** `UIDevice.batteryLevel` 为 -1
- **THEN** 报文不含 `batteryLevel`

### Requirement: 跑者端接收走散响铃
跑者端收到 `APP_NOTIFICATION` 且 `eventType=RUNNER_RING_LOST` 时 SHALL 与 `RUNNER_RING` 走同一套响铃：朗读 `ttsText`（缺失时用「你的陪跑员在找你，请原地停下」），随后循环提示音到 `until`，任意操作即停，同一 `messageId` 重复投递不重响，缺 `until` 或已过期时回落为普通通知朗读一次。响铃遮罩 MUST 使用走散文案（标题「请原地停下」），MUST NOT 出现「你的陪跑员到了」。

#### Scenario: 跑步中收到走散响铃
- **WHEN** 跑者端收到 `RUNNER_RING_LOST`，`until` 为 10 秒后
- **THEN** 不进横幅，响铃遮罩出现，读屏标签以「你的陪跑员在找你，请原地停下」开头，10 秒后自己停

#### Scenario: 走散响铃缺 until
- **WHEN** 跑者端收到不带 `until` 的 `RUNNER_RING_LOST`
- **THEN** 不响铃，作为普通通知朗读一次 `ttsText`

