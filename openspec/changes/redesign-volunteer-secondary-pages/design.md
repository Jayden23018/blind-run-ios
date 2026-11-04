## Context

见 proposal.md。约束：#696 还开着，它新增的 `AppColors.VolunteerHome`（天青 / 橙 / 琥珀卡名色）在 main 上不存在；本变更不碰 `AppColors.swift`、不新增颜色。部署目标 iOS 16。

## Goals / Non-Goals

**Goals:**
- 四页用首页 v3 的卡片语言：浅灰页底 `AppColors.Flow.page`、白卡 `AppColors.Flow.surface`、圆角 22、彩色卡名 + 图标。
- 能写单测的逻辑都放在视图外（月份序列、提要结论、格子数、评价档位、徽章目录与状态）。

**Non-Goals:**
- 首页评分卡可点（#696 合并后单开 PR）。
- 新奖章种类（Jayden23018/blind-run-backend#923）。
- 搭档「一起跑过几次」（陪跑员端契约没有这个字段）。

## Decisions

1. **颜色只映射到现有色值。** 一个文件内的 `VolunteerSecondaryTint` 把「卡名色」角色映射到已有值：陪伴时长 = 亮色 `Flow.stateRunning`（`#0A6B72`）/ 暗色 `paceMid`（`#19B3A6`）；连续陪跑 = `warning`；评分 = `Flow.replyUrgentText`；里程、星级、陪跑次数 = `primary`。这些值都已存在，亮暗都过 4.5:1。#696 合并后改指 `AppColors.VolunteerHome`。备选「在本 PR 加新色」被否：会和 #696 冲突，且违反设计文档 §2。
2. **奖章用 SwiftUI 形状自绘，渐变取现有色。** 六边形 / 圆 / 盾形三种 `Shape`，银边用白→`Flow.decorMuted`→白，金边用 `Flow.gold`→`Flow.ctaStroke`，面色用 `primary`/`Flow.navy`、`activeRunSurface`、`Flow.cta`/`Flow.stateArrived`；未获得 = `Flow.surfaceSubtle` 底 + `Flow.decorMuted` 线。备选「切图」被否：不随明暗与字号变化。
3. **7 枚徽章目录写在客户端**（`VolunteerBadgeCatalog`）：code → 名称、类别、形状、刻字、获得条件。后端只给已解锁的与一枚 `nextBadge`，画未获得的必须有这张表；服务端名字优先，目录只兜底。未知 code 的已解锁徽章进「其他」一块，用默认圆章。
4. **月度数据 6 次并发请求**，放在 `VolunteerServiceTrendLoader`（`withTaskGroup`），单月失败记为缺失。只用 async/await。
5. **搭档详情页由列表传入闭包**（退出、拉黑后的回调），退出成功后详情页关闭、列表重拉并显示结果，仍只有列表一个数据源。
6. **`CounterpartSafetyActions` 加一种「分组行」外观**（默认值不变），确认框和文案仍是同一份；备选「复制一份」被否：两份确认文案会漂移。
7. **成就页与徽章页从 `VolunteerOrderFlowViews.swift`（3700+ 行）挪到新文件**，`VolunteerAchievementsViewModel` 留在原处不动。

## Risks / Trade-offs

- [成就页每次进来多 6 个请求] → 低频页面，并发发出；失败不影响其余内容。
- [客户端徽章目录与后端漂移] → 名称以服务端为准；目录只管未获得的显示；新 code 走「其他」降级。后端加徽章时要同步（写进 PR 交接）。
- [#696 合并前卡名色与首页略有差异（暗色天青取 `paceMid`）] → 合并后单开小 PR 改指同一组色。
