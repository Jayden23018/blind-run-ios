## Context

首页「连续陪跑」半宽卡由 `VolunteerHomeHalfCard.left` 生成，数据来自 `VolunteerHomeIncentiveModel`：`partners/streaks` 的第一条。跑后记录月度列表 `RunRecordService.monthlyRecords` 一次只取一个月，没有跨月汇总端点。定稿与每个数字的算法在设计存档 `2026-11-05-volunteer-run-data/final/run-data-final.html` 的页内脚本里。

## Goals / Non-Goals

**Goals:**
- 照定稿做出跑步数据页的八块内容，所有数字由一个纯函数算出，可单测。
- 结论卡与首页卡在结构上保证是同一条火花。
- 每张图对读屏是一个元素并带一句摘要；AX3 及以上日历换成按月列表。

**Non-Goals:**
- 不做「日」档、不做左右滑看上一段。
- 不请后端加字段；不画配速趋势、每周时长。
- 盲人端「本月锻炼」不动。

## Decisions

1. **聚合写成纯函数 `VolunteerRunDataSummary`**（只依赖 Foundation）。输入：已加载的月度响应、`now`、`Calendar`（ISO 8601、本地时区）。输出：日历格、四档里程、时长柱、提要、搭档次数、个人纪录。视图不做任何计算。
2. **同一条火花**：`VolunteerHomeIncentiveSummary` 多带一个 `streakLastCreditedWeek`，首页 `halfCard` 把摘要里的火花、姓名、周号原样传给数据页。页面不重拉火花 —— 重拉在两次请求之间数据变化时会和首页卡对不上。
3. **本周周号**：用 `Calendar(identifier: .iso8601)` 的 `yearForWeekOfYear` 与 `weekOfYear` 拼 `YYYY-Www`，与 `lastCreditedWeek` 做字符串比较。
4. **取数**：`withTaskGroup` 并发 12 个月，每个月回来就写进字典并重算摘要（先到先画）。累计里程、累计陪伴取首页已加载的 `achievements`，不另发请求。
5. **平均的分母**：半年档 = 26 周，年档 = 12 个月；当前周（月）还没有公里数时不算进分母，避免月初、周一把平均拉低。
6. **颜色**：卡名色用 `AppColors.VolunteerHome` 现有的橙（连续）、天青（时长），新加靛蓝（里程）一色进 `cardTitleTones`，由 `VolunteerHomeColorContrastTests` 一起验。日历五档深浅色放在 `AppColors.VolunteerHome.calendarLevelTones`，只当图形用；信息另有文字与读屏摘要。
7. **图表**：柱图用 Swift Charts（iOS 16 可用，`VolunteerRunRecordView` 已在用）。日历用一个 `Canvas` 画 182 格，不建 182 个视图。

## Risks / Trade-offs

- 12 个请求较多 → 首屏先画到的月份；后端每次请求最多补算 5 张历史缩略图，只影响上线前的老单。
- 后端时间串是北京时间、无时区；客户端按 `backendTimestamp` 解析后，用本地时区的 ISO 日历归天、归周。手机不在东八区时，零点附近的一单可能落到相邻那天 → 国内用户本地时区就是东八区，不另做换算。
- 日历最浅一档对白底对比度不足 3:1 → 颜色不是唯一信息：卡上有陪跑天数，读屏与 AX3 列表给出每月天数。
