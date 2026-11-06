# 约跑页日期选择怎么做成真实可用（2026-11-07）

起因：负责人走 v4 约跑页（#806），发现日期只能选这一周、滑不到下一周，月份那一排点不了。实现 issue #821。

## 本仓库与后端的事实（读代码，不是联网）

| 事实 | 出处 |
|---|---|
| 日期只有 7 个，因为写死了 `maximumBookingLeadDays = 7` | `blindRun/Core/EnvironmentConfig.swift`、`BookingSlotPlanner.days` |
| 7 与后端上限一致：`app.order.max-lead-days=7`，超出回 422 `APPOINTMENT_TOO_FAR` | 后端 `application.properties`、`OrderCreationService.java`（origin/main，2026-11-07 读） |
| 月份那一排是装饰：固定画前后各两个月，`accessibilityHidden(true)`，没有点击 | `BookingDateStrip.monthRow` |
| 约跑页没读 `launchScope.dutyWindows`，值守时段外的时段也能选，提交后才 422 `APPOINTMENT_OUTSIDE_DUTY_HOURS` | `BlindMatchFirstBookingView`、`RuleParamsModels.swift` |

负责人 11-07 定：上限放宽到 30 天，月份可点（后端 Jayden23018/blind-run-backend#935）。

## 外面怎么做（联网）

| 结论 | 来源 | 等级 |
|---|---|---|
| 横滑列表做成**一个**「可调整」元素：读屏上下轻扫换一项，不用逐项左右扫 | Apple 文档 [Delivering an exceptional accessibility experience](https://developer.apple.com/documentation/accessibility/delivering_an_exceptional_accessibility_experience) 的 carousel 一节（JSON 原文已抓：「Swipe up to move forward through the collection」） | 官方原文 |
| 像选择器的横排（例如 Messages 的 Animoji 选择器）用单个可调整元素最合适；可调整元素会盖掉自定义操作 | [Apple 开发者论坛 781557](https://developer.apple.com/forums/thread/781557) | 论坛，转述 |
| 周日期条跨月时，「用标题说明当前时间范围」；翻周时「点箭头和横滑两种都给，不要只给一种」 | [Homebase 设计系统 Weekday Picker](https://designbase.joinhomebase.com/latest/components/weekday-picker/usage-wngae8X7)（fetch 原文） | 设计系统原文 |
| 范围外的日期画成不可选并留在原位，不藏起来 | 通行做法，多个组件库文档（WebSearch 转述） | 转述 |

## 用到 v5 稿上的做法

- 标题写真实年月；月份胶囊只列可约范围覆盖的月份（30 天最多两个月），点了跳到该月第一个可约日。
- 按周一到周日分页，箭头与横滑都能翻周，下方小圆点标第几周。
- 读屏把整条日期做成一个可调整元素，上下轻扫换一天，念「明天，11 月 8 日，周日」。
- 今天以前浅灰字；超出范围或没有值守的日期画虚线圈，不藏。
- 时段与后端值守时段取交集，提示句原样用后端 `dutyHoursHint`。

## 没查到

- 国内挂号 / 预约类 App 日期条的真实界面原文或截图（只有组件库文档）。
- Apple 对「可调整元素里元素数量上限」没有说法；30 天约 30 项，轻扫次数可接受，未实测。
