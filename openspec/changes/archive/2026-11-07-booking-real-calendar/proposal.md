## Why

负责人 2026-11-07 走 v4 约跑页（#806）反馈（#821）：「从哪出发」字小、和下面分不开，「当前位置 / 常用地点」两个胶囊看不出区别；日期只能选这一周、滑不到下一周；月份那一排点不了 ——「仿照了界面，没有仿照逻辑」。

查下来：日期只有 7 个是写死的 `maximumBookingLeadDays = 7`（与后端 `app.order.max-lead-days` 旧值一致）；月份排是装饰；约跑页没读后端值守时段，值守时段外的时段也能选，提交才 422 `APPOINTMENT_OUTSIDE_DUTY_HOURS`。

## What Changes

- 可约天数读 `GET /api/config/rules` 新字段 `maxLeadDays`（后端 Jayden23018/blind-run-backend#935 放宽到 30 天），缺省或非正数退回 7。
- 日期改成真实日历：真实年月标题、周一到周日分页、翻周箭头与横滑、月份胶囊只列有可约日子的月份并可点；读屏一周是一个可调整元素。
- 时段与后端值守时段（`launchScope.dutyWindows`）取交集；整段不在值守里的灰掉并写原因；后端 `dutyHoursHint` 原样显示。
- 「从哪出发」换成「默认出发地点」页同一套彩色圆排：当前定位、全部常用地点、添加；进页默认选首页设的默认出发地点。

## Impact

- 契约用法：新读 `RuleParamsResponse.maxLeadDays`（backend#935），新用 `launchScope.dutyWindows` 裁时段。
- `blindRun/BlindRunner/BlindMatchFirstBookingView.swift`、`BookingDateStrip.swift`、`BookingSlotPlanner.swift`、`BlindStartPlaceLibrary.swift`、`BlindFavoritePlaceAddPage.swift`、`BlindRunnerHomeView.swift`；新文件 `BookingCalendarModel.swift`、`BookingStartPlacePicker.swift`。
- `blindRun/Core/Models/RuleParamsModels.swift`。
- 陪跑员见面安排单：`blindRun/Volunteer/VolunteerMeetupPlan.swift`、`VolunteerMeetupPlanFormView.swift`、`VolunteerIntroCallView.swift`（最晚开跑时间跟着 `maxLeadDays`）。
