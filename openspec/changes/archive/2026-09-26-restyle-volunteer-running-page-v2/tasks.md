## 1. 纯类型与组件

- [x] 1.1 `VolunteerRunningHero`：里程 / 用时 / 配速、目标进度与文案、提示条优先级，附单测
- [x] 1.2 `FlowHelpPill` / `FlowOrderNavBar` 支持云端模式（读屏标签、identifier、发送中禁用）
- [x] 1.3 长按结束按钮换成填充样式，`ringProgress` → `fillProgress`，更新 `VolunteerFinishLongPressTests`

## 2. 页面接入

- [x] 2.1 `VolunteerRunningPage`：导航栏 + 藏青头卡 + 提示条 + 求助结果区 + 底部长按
- [x] 2.2 `VolunteerInServiceView` 在 `IN_PROGRESS` 走新页面，系统导航栏藏掉
- [x] 2.3 删除 `VolunteerEscortStatsCard`、`VolunteerSOSNavButton` 与旧路径里的跑步中分支
- [x] 2.4 保留「取消订单」灰色文字按钮（画布没画，旧页面有，→ `REMATCHING`）

## 3. 验证

- [x] 3.1 UI 用例改认新 identifier（审计两条、`blindRunUITests` 三条）
- [x] 3.2 编译门禁 `build-for-testing`
- [x] 3.3 真机跑覆盖的 suite，竖屏 / 横屏 / AX3 截图对照画布
- [x] 3.4 后端缺的能力各开一个 issue：节奏 blind-run-backend#443、暂停 #444、跑步中响铃 #445、值班电话 #446（电量后端已在 #322 答复「没有、近期不加」，不重开）
