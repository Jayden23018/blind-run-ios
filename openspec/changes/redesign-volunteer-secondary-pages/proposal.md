## Why

陪跑员首页已按 Apple「健康」摘要页重做（PR #696），点进去的四个二级页还是旧样子：固定搭档是一屏 9 个操作按钮，服务成就是一块实心蓝 + 灰格子，评分没有自己的页，徽章页只列已解锁的、点不动。负责人 2026-11-04 批准可视稿 v3（`docs/ui/mockups/volunteer-secondary-pages-20261104/`），要求四页用同一套设计语言（issue #697）。

## What Changes

- 固定搭档：列表一人一行（头像字、掩码名、连续周数或设为搭档日期、你已退出），整行进**新的搭档详情页**；「举报 / 不再匹配此人 / 退出固定搭档」从列表挪进详情页底部。空状态改成说明卡。盲人端「我的固定搭档」不变。
- 服务成就：头卡改成陪伴时长大数字 + 近 6 个月柱状图（逐月读跑后记录的 `serviceMin`）；提要卡（一句结论、细灰分隔线、本月与前 5 个月平均两根横条）；累计里程 + 评分两张半宽卡，评分卡进评分页；国标星级改成圆环（仍与平台勋章分两块）；徽章块（下一枚进度 + 已获得，「全部显示」任何时候都能进）。
- 评分（新页）：平均分 + 计分说明、好评徽章状态、最近的评价（很好 / 一般 / 无评分，点一行进那次跑后记录）。
- 徽章页：顶部「加油」= 下一枚；7 枚按类别分块，每类一种形状，未获得画灰线框；点开弹层看名称、状态、获得条件（不写日期）。客户端写死 7 枚 code 的名称与条件，未知 code 降级显示。
- 图表、圆环、进度条进页长出一次；点奖章放大翻转；全部跟随「减弱动态效果」。

## Capabilities

### New Capabilities
- `volunteer-secondary-pages`: 陪跑员端固定搭档（含搭档详情）、服务成就、评分、徽章四个二级页显示什么、数据从哪来、操作入口在哪。

### Modified Capabilities

（无。首页 `volunteer-profile-first-screen` 的「评分卡可点」等 #696 合并后另开小 PR。）

## Impact

- 代码：`blindRun/Shared/PartnerListViews.swift`、`blindRun/Shared/CounterpartSafetyActions.swift`（加一种「分组行」外观，默认外观不变）、`blindRun/Volunteer/VolunteerOrderFlowViews.swift`（成就页与徽章页挪到新文件）、`blindRun/Volunteer/VolunteerAchievements.swift`（7 枚徽章目录）、新文件若干。
- 接口：全部是现有接口 —— `/api/volunteer/favorites`、`/api/volunteer/partners/streaks`、`/api/volunteer/achievements`、`/api/orders/mine/run-records?month=`（成就页每次进 6 次）、`/api/volunteer/dispatch-summary`。不改后端。
- 不碰：`VolunteerHomeSummaryCards.swift`、`AppColors.swift`、首页 `VolunteerProfileFirstScreenView*.swift`（#696 在改）。
