# Tasks

## 1. 规则

- [x] 1.1 `RuleParamsResponse` / `RuleParams` 加 `maxLeadDays`（缺省或 ≤0 退回 7）；`LaunchScopeResponse.dutyMinuteRanges()`。
- [x] 1.2 `BookingSlotPlanner` 读 `BookingRules`：可约天数、值守时段交集、不能选的原因、具体时刻不晚于最晚开跑时刻。

## 2. 界面

- [x] 2.1 `BookingCalendarModel.swift` + 重写 `BookingDateStrip`：真实年月、翻周、月份胶囊、读屏可调整、大字档列表。
- [x] 2.2 `BookingStartPlacePicker`：彩色圆排（当前定位 / 常用地点 / 添加），进页默认选首页默认出发地点；添加页从约跑页进来时退回约跑页。
- [x] 2.3 时段胶囊加时间范围或不能选的原因；显示后端值守提示；三个问题标题加大、分组白卡。
- [x] 2.4 陪跑员见面安排单的最晚开跑时间改读 `maxLeadDays`（审查发现：写死 7 天时 8 天以后的时段单填不了安排单）。

## 3. 收尾

- [x] 3.1 `xcodebuild build-for-testing` 通过（2026-11-07，`** TEST BUILD SUCCEEDED **`）；`BookingCalendarTests` 14 条写好、只编译未执行（负责人 11-05 定不跑真机测试）。
- [x] 3.2 `docs/ui/mockups/INDEX.md` 加 v5 一行。
