# 志愿者端「我」首屏 · 设计稿（2026-09-14）

直接用浏览器打开 `01-final-screen.html` / `02-swipe-cta-states.html`，无依赖、无需起服务。
画布按 iPhone 14/15/16 的 **390 × 844 pt** 逐点对齐。

**这是设计稿，不是实现。** 落地前必须过 `docs/ui/ui-review-checklist.md`，
并按 `AGENTS.md` §1 判一次哪些约束该落成守卫或用例。

## 外部依据

调研报告：[`docs/research/volunteer-profile-first-screen-20260914.md`](../../../research/volunteer-profile-first-screen-20260914.md)
（Strava / Nike Run Club / Be My Eyes / HelpUnity / Rosterfy / Lasagna Love / 悦跑圈 共 15 组界面 +
Uber Base Sliding button 原文规格）

机制层依据沿用：[`docs/research/volunteer-home-incentive-layer-20260914.md`](../../../research/volunteer-home-incentive-layer-20260914.md)
（motivation crowding、不得折算金额、一屏一主指标、不得在下线时挽留）

## 每个字段的真实来源（本稿不含任何编造数据）

| 稿上的位置 | 字段 | 来源 |
|---|---|---|
| `24 次陪跑`（主指标） | `totalCompleted` | `GET /api/volunteer/achievements` |
| `186 小时` | `totalServiceMinutes` / 60 | 同上 |
| `8 位 固定搭档` | `volunteerFavoritedBy().count` | `GET /api/volunteer/favorites` |
| `4.9 · 32 条` | `avgRating` / `totalRatings` | `GET /api/volunteer/achievements` |
| `三星志愿者 186/300 小时` | `starLevel.current` / `currentHours` / `nextTarget` | 同上 |
| 已解锁徽章 3 枚 | `badges[]`（**只含已解锁**，未解锁不在列表里） | 同上 |
| `夜跑守护 3/5`（虚线圈） | `nextBadge.name` / `current` / `target`；全解锁时为 `null` | 同上 |
| 最近陪跑三行 | `order.createdAt` / `blindName` / `startAddress` / `status` | `VolunteerServiceRecord`（`VolunteerOrderFlowViews.swift:7`） |

⛔ **稿上刻意没有的三样**，理由见调研报告 §4，别在后续迭代里加回来：
累计里程（后端 spec 逐字「刻意没有」）、本月 N/M 目标（Moving Target）、时长折算金额（网信办 + 民政部令 67 号）。
⛔ 「证明 / 证书」字样不得出现 —— `/api/volunteer/achievements` 的 description 明令。

## 两条落地时必查的实现约束

1. **滑动 CTA 绑的是 `setAvailability(true)`**（`VolunteerHomeView.swift:765`），不是导航。
   它替代现有的 `Toggle`（`VolunteerHomeView.swift:1808`）。控件名的单一来源是
   `VolunteerHomeView.swift:16` 的 `toggleTitle = "可服务开关"`。
2. **摩擦力只加在「开启」一侧。** 关闭是普通点按，且不得弹任何挽留 ——
   这条已经以注释形式钉在 `VolunteerHomeIncentive.swift:100`，改 UI 时别把它绕过去。

## 配色

全部取自 `AppColors`（`blindRun/Core/DesignSystem/AppColors.swift`），未新增颜色：
`primary #0058C7` / `success #1B7F3B` / `warning #B25000`（仅用于星级与徽章，不承载警示语义）/
`textSecondary #5C5C61`。暖色感来自中性暖底 `#FAF6F1`（背景色，不承载文字对比度义务），
**没有引入 Strava 的品牌橙** —— `#FC5200` 压白底约 3.1:1，过不了 `AppColorContrastTests` 的 4.5:1。
