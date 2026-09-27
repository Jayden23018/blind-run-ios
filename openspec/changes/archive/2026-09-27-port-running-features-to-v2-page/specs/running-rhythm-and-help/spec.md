## MODIFIED Requirements

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
