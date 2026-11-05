## Why

陪跑员首页「连续陪跑」卡点进去是固定搭档列表：卡上说的是「连续几周」，点进去却是一张人名单。负责人 2026-11-05 要求照 Apple 健康 App 卡片详情页的结构，在这里展示跑步数据：不同时间范围累计多少公里，像 GitHub 提交记录那样看哪几天陪跑了。设计稿 v1 已批准（定稿 `docs/ui/mockups/volunteer-run-data-20261105/run-data-final.png`，issue #710）。

## What Changes

- 新增陪跑员「连续陪跑」跑步数据页：结论卡（和谁连续几周、本周记上没有、本周七天）、陪跑日历（近 26 周 × 7 天）、里程（周 / 月 / 半年 / 年，默认半年）、陪伴时长（近 6 个月按月）、提要三张、一起跑的人、个人纪录、固定搭档入口与规则说明。
- 首页「连续陪跑」半宽卡（有连续周数时）改去这一页；「固定搭档 N 位」那种退化卡仍去固定搭档页。
- 只用现有契约：`GET /api/orders/mine/run-records?month=`（近 12 个月，并发拉，先到先画）、`GET /api/volunteer/partners/streaks`、`GET /api/volunteer/achievements`。不请后端加每次时长 / 配速，所以不画配速趋势与每周时长。
- 新增一个卡名色「里程靛蓝」（`AppColors.VolunteerHome.distanceIndigo`）和陪跑日历的五档深浅色，配对比度用例。
- Mock 加一份近半年、有起伏的样例跑步记录，用 launch 环境变量打开。

## Capabilities

### New Capabilities
- `volunteer-run-data`: 陪跑员「连续陪跑」跑步数据页的内容、取数口径与无障碍要求。

### Modified Capabilities
- `volunteer-profile-first-screen`: 首页卡片去处 —— 连续陪跑卡去跑步数据页，不再去固定搭档页。

## Impact

- 新文件：`blindRun/Volunteer/VolunteerRunData*.swift`、对应单测与 UI 用例。
- 改动：`VolunteerProfileFirstScreenView+Impact.swift`（`halfCard` 去向）、`VolunteerHomeIncentive*.swift`（摘要多带一个 `lastCreditedWeek`）、`AppColors.swift`、`MockAPIClient+RunRecord.swift`。
- 盲人端「本月锻炼」不动；后端契约不动。
