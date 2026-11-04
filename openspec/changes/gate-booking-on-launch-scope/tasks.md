## 1. 数据与会话

- [ ] 1.1 `RuleParamsModels.swift` 解码可选 `launchScope`（宽容解码，坏数据当 nil），加 `contains` / `admits` 纯函数
- [ ] 1.2 `AppState` 规则参数按账号：登出清空、换账号丢弃迟到结果、支持强制重读、记下「后端刚说暂未开放」
- [ ] 1.3 Mock `/api/config/rules` 返回无限制的 `launchScope`，并能为 UI 测试注入「暂未开放」

## 2. 盲人下单

- [ ] 2.1 首页入口闸门：暂未开放显示并播报 `areaHint`，只给返回首页，不进表单、不启动语音向导
- [ ] 2.2 表单出发地点一步显示 `areaHint`，预约时间一步显示 `dutyHoursHint`，超出范围时说明；无限制时不显示
- [ ] 2.3 提交逻辑搬进扩展文件；`ORDER_OUTSIDE_OPEN_AREA` 回出发地点、`APPOINTMENT_OUTSIDE_DUTY_HOURS` 回预约时间、`ORDER_SERVICE_NOT_OPEN` 换告知页

## 3. 错误码与见面安排单

- [ ] 3.1 三个码加入 `ErrorCode` 与 `prefersServerMessage`，兜底文案放扩展文件（#677 合并后）
- [ ] 3.2 见面安排单两个码落在时间 / 集合地点那一块

## 4. 验证

- [ ] 4.1 单测：解码（缺字段 / 坏字段）、范围判定边界、账号切换、三个错误码各一条、见面安排单两条；真机集中验红再验绿
- [ ] 4.2 UI 测试：暂未开放时进入下单页不出现表单与语音向导，截图
- [ ] 4.3 SwiftLint 棘轮 rc=0、spec 覆盖校验、错误码对撞
