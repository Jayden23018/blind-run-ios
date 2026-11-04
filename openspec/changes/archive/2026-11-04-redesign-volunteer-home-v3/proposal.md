## Why

负责人 2026-11-04 定稿「陪跑员首页 v3」（Jayden23018/blind-run-ios#694，样例 `docs/ui/mockups/volunteer-home-v3-20261104/`）：首页只回答「我做过什么」，接单的东西全部放进已有的接单页。现在首页底部压着一条饱和绿色通栏，最底下还有一块派单状态框和定位文字，两页的分工不清。

## What Changes

- 首页顶部改为大标题「首页」+ 右上角头像（进设置），去掉身份行。
- 首页内容装进白色圆角卡片，分区标题加粗：陪伴时长卡 → 连续陪跑 + 评分两张半宽卡 → 最近陪跑 → 徽章。「需要你处理」（含预约待确认，#463）仍在最上方。
- 陪伴时长卡合并原来的星级卡：大数字 + 「共陪跑 N 次」+ 到下一星级的进度条。三列统计删掉，累计里程不再上首页。
- 最近陪跑卡改用 `GET /api/orders/mine/run-records`：公里数、对方脱敏姓名、地点、陪跑员路线缩略图（`thumbnail` 为空不画）；本月没有记录退到上月。
- **删掉首页的派单状态框和定位文字**，搬进接单页顶部的状态卡。
- 底部入口改成白色底座里的一枚胶囊：没在接单是蓝色滑块（向右滑开启并进入接单页）；接单中是浅绿底深绿字「接单中 · 进入接单」，点按进入接单页。**不再支持向左滑动停止接单**，停止走接单页的「暂停接单」（读屏的「停止接单」动作保留）。
- 接单页换成同一套卡片样式：状态卡 → 下一次陪跑 → 待回复邀请 → 空闲时间 / 之后的陪跑 → 暂停接单。
- 新增一对颜色 `availabilityPillSurface` / `availabilityPillText`（亮色 `#E3F2E7` / `#155E2C`），亮暗两套都有对比度用例。

## Capabilities

### New Capabilities
<!-- 无 -->

### Modified Capabilities
- `volunteer-profile-first-screen`: 首屏结构、最近陪跑数据源、底部入口与接单页分工变化。

## Impact

- 代码：`blindRun/Volunteer/VolunteerProfileFirstScreen*.swift`、`VolunteerHomeView.swift`、`VolunteerAvailabilitySlider.swift`、`VolunteerDispatchHubView.swift`、`blindRun/Core/DesignSystem/AppColors.swift`。
- 接口：多一次 `GET /api/orders/mine/run-records`（记录标签页已在用，契约无改动）。
- 测试：首页与接单页相关 UI 用例、无障碍审计、`LowVisionChannelTests` 对比度用例。
- 不做：「我的」页、二级页、固定搭档页、盲人端；样例里「置顶」旁的「编辑」。
