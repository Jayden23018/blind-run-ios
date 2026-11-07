# 跑步记录列表怎么看别的月份（2026-11-07）

负责人嫌「上个月：10月 ›」「下个月：12月 ›」两行按钮难看，问有没有优雅、简洁、好用的切月方式；备选是只显示本月。

## 别家怎么做

| 产品 | 做法 | 来源（2026-11-07 读过原文） | 等级 |
|---|---|---|---|
| 苹果「健身」→ 摘要 → 历史「显示更多」 | 一条连续列表，按日期和月份列出，往下滑看更早的；没有切月按钮。可按运动类型筛选 | [iDownloadBlog](https://www.idownloadblog.com/2016/10/27/how-to-look-back-at-your-weekly-move-goals-progress-in-the-activity-app/)（2024 年更新，含截图） | 二手，带截图 |
| Nike Run Club | 活动页顶部看本周 / 本月 / 本年 / 全部的汇总，下面滚动全部跑步，可筛选 | [Nike 帮助中心](https://www.nike.com/help/a/nrc-activity) | 官方，搜索摘要转述 |
| Strava 训练日志 | 默认按周；手机端右上角日历图标跳到某个月或某年 | [Strava 帮助中心](https://support.strava.com/hc/en-us/articles/206535704-Training-Log) | 官方原文 |

查到的三家都**没有**「上个月 / 下个月」两行按钮。Keep、Garmin Connect 没查到界面说明。iOS 26 健身「历史」是否还是按月分节，只有第三方 2024 年的截图，未在真机上确认。

## 结论

推荐照健身：一条按月分节的列表，每节标题「11月」+「跑了 N 次 · X 公里」，往下滑自动接上更早的月份，到第一次跑步的月份为止；没跑步的月份不出现。第一屏就是「本月记录」，覆盖负责人「只显示本月」的想法，又不丢历史。

- 不改后端：每月照旧调 `GET /api/orders/mine/run-records?month=`；到底的月份用已完成订单里最早一单判断（`GET /api/orders/mine` 按 `createdAt` 倒序分页）。
- 推翻 2026-09-24 的「一次一个月、不往下追加」（`docs/ui/mockups/run-record/DECISIONS.md:99`），要负责人点头。
- 「只显示本月」被否的原因：每月 1 号清零，上个月的跑步与留言在 App 里再也打不开。

设计稿：`docs/ui/mockups/run-record-polish-20261107/draft.html`。
