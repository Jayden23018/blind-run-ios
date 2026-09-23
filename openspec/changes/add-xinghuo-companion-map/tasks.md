# Tasks

## 1. 一期（纯 iOS，调试版）

- [x] 1.1 `blindRun/Map/AMapContainer.swift`：地图跟随系统明暗（`standardNight` / `standard`），
      新增 `volunteerStar` / `runnerCluster` 两种自绘标注（`XinghuoGlyph`，色取 `AppColors.tones`），
      `MapPolylineItem.isFootprint`；明暗切换时标注与足迹线一起重画。
- [x] 1.2 `blindRun/Xinghuo/XinghuoSnapshot.swift`：快照模型（= 二期契约形状）、摘要句、分档、
      今日足迹筛选、`#if DEBUG` 演示数据生成器。
- [x] 1.3 `blindRun/Xinghuo/XinghuoMapView.swift`：页面（两端共用，按角色区分密度与文案）。
- [x] 1.4 两端 TabView 各加 `#if DEBUG` 的「星火」tab。
- [x] 1.5 `blindRunTests/XinghuoSnapshotTests.swift`；`AccessibilityAuditTests` 两条 tab 用例补「星火」+ 盲人端星火页审计。
- [ ] 1.6 真机：跑 1.5 的用例与轨迹地图相关套件；亮暗两种模式下目视四处地图（下单选点 / 志愿者服务中 / 轨迹回放 / 星火页）。
      UI 测试构建没有高德 key，地图恒为占位图 ⇒ 视觉只能手动装真 key 构建看。
      **专门盯明暗切换那一刻**：星形标注重画、足迹线删掉重加（`AMapContainer.applyColorScheme`，单测够不着）；
      以及既有轨迹主线的 `systemBlue` 在高德渲染里是否跟着切换（既有路径，未验证过）。
- [ ] 1.7 低视力对比度：夜间与标准底图上金星、蓝点的图标对比度（≥3:1），`LowVisionChannelTests` 不覆盖，人工量。

## 2. 二期（需要后端）

- [ ] 2.1 后端聚合端点（需求见 `demo/docs/handoff.md` 2026-09-23 条目）：返回 `XinghuoSnapshot` 同形状 ——
      `regionName`、四个计数、`todayRuns`、`cells[{center, kind, count}]`；**网格化与 k 阈值在服务端执行**，
      低于阈值的格子归并到更粗一级而不是隐藏；不下发任何个人坐标；动态只给汇总。
- [ ] 2.2 iOS 接真数据，去掉 `#if DEBUG` 闸与演示数据生成器，正式上线。
- [ ] 2.3 送审口径：本页是「以用户所在城市为范围」的局部地图 —— 上线前按 09-21 调研复核是否需要审图号。

## 3. 另起变更

- 声音化（戴耳机时启用，按距离依次播放最近几位）。
- 摘要方位用绝对方位还是相对方位 —— 先问视障用户。
- 志愿者之间互相联系约跑。
