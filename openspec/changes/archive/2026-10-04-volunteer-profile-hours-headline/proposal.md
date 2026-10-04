## Why

2026-10-03 志愿者试用反馈：首页最大的数字是公里，像一个跑步 App；志愿者在乎的是「陪了别人多久」。项目负责人当日拍板把主指标改成陪伴时长，替代 #269 的累计公里。同一轮反馈指出「0 位 固定搭档」与「尚未达到一星」是负面表达。

## What Changes

- 主指标：陪伴时长（`totalServiceMinutes` 向下取整成小时）满 1 小时时显示「N 小时」，下一行「共 M 次陪跑」；不足 1 小时回落到「M 次陪跑」，不显示「0 小时」。
- 三列统计第一格由「陪伴时长」换成「累计里程」；不足 1 公里显示 `--`。
- 固定搭档为 0 时显示 `--`，读屏念「还没有跑者把你设为固定搭档」。
- 首屏星级卡未到一星时标题为「距离一星还差 N 小时」，进度行「已累计 X / 100 小时」，读屏同口径。成就页文案不变。
- 同一轮反馈的非行为性修正（不进规格）：徽章名「陪跑达人 · 10 次」拆两行；陪跑员跑后详情自己的头像写「我」；路线外框不足 10 米时缩略图画跑步图标；滑轨文案改为「向右滑动，我现在有空陪跑」。

## Capabilities

### Modified Capabilities
- `volunteer-profile-first-screen`：主指标由累计公里改为陪伴时长。

## Impact

- `blindRun/Volunteer/VolunteerProfileFirstScreen.swift`、`VolunteerProfileFirstScreenView.swift`、`VolunteerRunRecordView.swift`、`VolunteerAvailabilitySlider.swift`、`blindRun/Shared/RunRecordHistoryView.swift`。
- 测试：`VolunteerProfileFirstScreenTests`、`RunRecordHistoryTests`；UI 测试按新滑轨文案找按钮。
