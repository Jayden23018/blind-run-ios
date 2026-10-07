# Tasks

- [x] 1.1 完成页星级进度卡（`VolunteerStarProgressCard`，由成就页 `starSection` 提出）；任务挂在整页上，避开空视图上的 `.task`。
- [x] 1.2 成就页主数字卡主色实心；勋章预览改圆形徽章一排（`VolunteerBadgeMedallion`，由首页 `badgeCellBody` 提出），AX 档退回逐行。
- [x] 1.3 两端「我的」标签根页：标题「我的」+ 个人卡；齿轮入口仍「设置」。UI 用例按标题找页面的两处跟改。
- [x] 1.4 汇合页无方向时不画方位盘。
- [x] 1.5 Mock：`COMPLETED` 种子带 `completedTogetherCount`。
- [x] 2.1 `build-for-testing`；真机跑覆盖的 suite（`VolunteerAchievementsTests`、`VolunteerProfileFirstScreenTests`、`VolunteerOrderV2Tests`、`RunRecordHistoryTests` 与改到标题的 UI 用例）。
- [x] 2.2 截图巡游改后逐屏自读 + 零上下文复评；`docs/ui/mockups/INDEX.md` 记偏差。

> 2026-10-05：真机 iPhone 16 Pro 一批 `passed=187 failed=0`（7 个单测 suite + 10 条改到标题 / 齿轮路径的 UI 用例 + 3 条审计 + 重拍 B33）。
> 改后截图逐屏自读：4 处到位；跑者「我的」本月 0 次的否定句已改为不显示。零上下文复评：志愿者端易用 6.7 → 7.1。
> INDEX 偏差已记（方位盘、完成页星级卡）。本变更可在开 PR 时归档。
