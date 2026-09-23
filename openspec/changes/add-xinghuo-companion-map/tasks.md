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
      （1.8 之后星火页固定夜空：星芯压夜空底 ≥3:1 已由 `testXinghuoPaletteKeepsTextReadableOnGlass` 钉住；
      剩下的是叠在高德 `standardNight` 真实底图上的观感，仍要人工看。）

### 1.8–1.13 照原型重做（2026-09-23 负责人真机反馈 5 条）

原型：`~/Downloads/星火同行 · 助盲跑陪伴地图 MVP.html`。负责人当日拍板：星火页**固定夜空**、
原型配色进 `AppColors.Xinghuo`、底图先用 SDK 开关（控制台样式以后再接）、调试版补演示足迹。

- [x] 1.8 地图拖不动：浮层去掉全屏 `ScrollView`，改成「顶栏 + 空白 + 贴底卡片」，卡片常驻滚动容器按内容定高
      （`HugContentHeight`，照搬 PR #181）；`AMapContainer.snapsBackToCenter` 开关（星火关掉，刷新不再把地图拽回去）；
      中心锁在首次位置；「回到我的位置」按钮；星火页 `maxRenderFrame` 30。
- [x] 1.9 星星像棋盘：`XinghuoSnapshot.sparks` 按 `cell.id`（FNV-1a）把片区确定性散成一小簇（≤12 颗、半径 180 m 不出片区），
      大小 / 亮度 / 旋转 / 闪烁节奏各不同；演示数据改为热点撒点。数据契约不变。
- [x] 1.10 动效：`XinghuoSparkView`（Core Animation）从「你」向外按距离点亮 + 白色闪光、光晕闪烁；
      `XinghuoSelfView` 三圈扩散环 + 「你」气泡；足迹光带双层线 + `MAAnimatedAnnotation` 流动光点。
      「减弱动态效果」时一个动画都不加，运行中切换当场生效。
- [x] 1.11 底图像夜空：`AMapContainer.nightSky`（关路名 / 店铺 / 楼块 / 比例尺 + 道路之上一层深蓝压淡）+ SwiftUI 四周压暗；
      整页锁 `.dark`（design-direction §2 记为例外）。
- [x] 1.12 卡片与数字：`AppColors.Xinghuo` 深色玻璃、金色衬线大数字、字标、图例；「听见星光」用 `FlowActionButton` 金色主按钮。
- [ ] 1.13 验证：编译门禁；真机跑 `XinghuoSnapshotTests` / `LowVisionChannelTests` / 星火审计用例（新增「卡片滚动容器不盖住上半屏」断言）；
      带真 key 的调试版由负责人目视（拖动跟手、点亮顺序、闪烁、光点、压淡程度、减弱动态效果、iPhone + iPad）。
      可调参数：压淡层 α0.5、`maxRenderFrame` 30、光点 400 m/s。控制台自定义样式另起一项。
      共用 `AMapContainer` 的回中心判据改过（默认行为推理上等价）：真机顺带过一遍非星火页的地图
      （下单选点 / 志愿者服务中 / 轨迹回放）有没有抖动。
      - [x] 拖动：2026-09-23 真 key 调试版（a25d53a + 临时插桩），iPhone 16 Pro 两端各拖 / 捏若干次 ——
            触摸全部落在 `MAMapView` 子树上，高德回 32 次 `regionDidChange(wasUserAction: true)`，中心与缩放都跟手变。
            负责人先前「拖不动」的反馈是对 1.8 之前的全屏 `ScrollView` 版，本版已不复现；
            防回退的检查是审计用例里「卡片滚动容器 minY > 屏高 × 0.4」（已验红）。

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
