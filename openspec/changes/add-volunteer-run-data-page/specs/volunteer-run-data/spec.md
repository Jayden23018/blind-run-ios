## Purpose

陪跑员「连续陪跑」跑步数据页：照健康 App 卡片详情页的结构，先给结论，再给陪跑日历、里程、陪伴时长等图，最后给提要、个人纪录和固定搭档入口。数据只来自现有契约。

## ADDED Requirements

### Requirement: 结论卡与首页卡说的是同一对搭档
跑步数据页顶部结论卡 SHALL 显示首页「连续陪跑」卡上的同一位搭档和同一个连续周数（`GET /api/volunteer/partners/streaks` 的第一条），并显示最好周数。「本周记上没有」SHALL 用这一条的 `lastCreditedWeek` 和按 ISO 8601 日历算出的本周周号（如 `2026-W45`）比较，SHALL NOT 把 `lastCreditedWeek` 当日期解析。下面七个圆 SHALL 表示本周一到周日哪几天有完成的陪跑（与任何搭档），有陪跑的那天 SHALL 画对勾，不只靠颜色。

#### Scenario: 本周已记上
- **WHEN** 第一条火花的 `lastCreditedWeek` 等于本周 ISO 周号
- **THEN** 结论卡写「本周已经和 <搭档> 跑过，这一周记上了」

#### Scenario: 本周还没记上
- **WHEN** `lastCreditedWeek` 是上一周
- **THEN** 结论卡说明本周还没和这位搭档一起跑，跑完一次就记上

### Requirement: 陪跑日历一格一天
陪跑日历 SHALL 画近 26 周（本周一往前 25 周）× 周一到周日的格子，一格一天，深浅按当天完成陪跑的公里数分档；今天之后的格子 SHALL NOT 画。卡上 SHALL 显示近半年陪跑天数和最长连续周数。按周归组 SHALL 用 ISO 周（周一开头）、本地时区。`distanceM` 为 null 的记录 SHALL 算作陪跑过的一天，但 SHALL NOT 当 0 公里计入任何公里数或平均。「最长连续」SHALL 与任何搭档都算，客户端按周数。

#### Scenario: 读屏听日历
- **WHEN** VoiceOver 聚焦陪跑日历
- **THEN** 整张图是一个元素，念「近半年陪跑 N 天，最长连续 M 周」，再按月念每月跑了几天、哪几日

#### Scenario: 无障碍大字号
- **WHEN** 字号是 AX3 或更大
- **THEN** 格子图换成「月份 + 跑了几天」的按月列表

### Requirement: 里程分四档，默认半年
里程卡 SHALL 提供「周 / 月 / 半年 / 年」四档，默认「半年」。周档画本周 7 根日柱、图头写总计；月档画本月每天一根、图头写总计；半年档画 26 根周柱、图头写平均每周；年档画近 12 个月每月一根、图头写平均每月，平均档 SHALL 画平均虚线。还没结束的本周（本月）如果还没有公里数，SHALL NOT 算进平均的分母。卡底 SHALL 显示累计里程，取 `achievements.totalDistanceMeters`，SHALL NOT 用这 12 个月相加代替。

#### Scenario: 切到年
- **WHEN** 志愿者点「年」
- **THEN** 图换成 12 根月柱，图头写平均每月公里数与起止月份，读屏摘要同步换成年档那一句

### Requirement: 陪伴时长只按月
陪伴时长卡 SHALL 画近 6 个月每月一根柱（`monthSummary.serviceMin`），图头写平均每月，卡底写累计陪伴（`achievements.totalServiceMinutes`）。页面 SHALL NOT 画配速趋势和每周时长（契约里没有每次的时长与配速）。

#### Scenario: 没有每次时长
- **WHEN** 页面加载完成
- **THEN** 页面上没有配速图，陪伴时长只有按月的柱

### Requirement: 提要、一起跑的人与个人纪录
页面 SHALL 显示三张提要：上月与前月的里程对比、近半年最常陪跑的星期、最远的一次（有路线缩略图时画缩略图，没有时只写文字）。「一起跑的人」SHALL 按近半年与每位搭档完成的次数排列，对方已注销（名字为空）的合成「已注销的跑者」一行。个人纪录 SHALL 显示最远一次、单周最多次数、单周最远公里、最长连续周数。页底 SHALL 有「固定搭档」入口（去固定搭档页）和连续周数的规则说明。

#### Scenario: 对方已注销
- **WHEN** 近半年有两次记录的 `partnerName` 为 null
- **THEN** 「一起跑的人」里有一行「已注销的跑者 2 次」

### Requirement: 并发取数，先到先画
页面 SHALL 并发请求近 12 个月的月度列表，每到一个月就重算一次图；有月份失败时 SHALL 显示可见的提示和重试按钮，只重拉失败的月份。

#### Scenario: 一个月失败
- **WHEN** 12 个月里有 1 个月请求失败
- **THEN** 其余月份照常画出，页面显示「有 1 个月的记录没加载出来」和「重试」
