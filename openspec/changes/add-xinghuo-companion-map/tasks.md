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

### 1.14–1.15 底部卡片可收起（2026-09-23 负责人：「有的人想更多的界面在地图上，就可以把这个划下去」）

负责人拍板：两档；默认展开；档位跨启动记住；收起态 = 一行「N 位志愿者在线」+「听见星光」+ 足迹开关 + 演示角标，
盲人端两者整行竖排（design-direction §4「绝不并排」），志愿者端并排（密度轴），大字号时志愿者端也竖排。

- [x] 1.14 `XinghuoMapView`：卡片顶上加把手（盲人端 64pt / 志愿者端 44pt 命中区），拖动只挂在把手上
      （不跟卡片里的 `ScrollView` 抢手势），轻点也能切换；`@AppStorage` 记档位；读屏：把手是按钮 +
      可调节（上下轻扫展开 / 收起），排在卡片内容之后，摘要句仍是第一个读屏元素；减弱动态效果时不跟手、不做弹簧，直接到位。
      不用 `.sheet` + `presentationDetents`（模态会挡住地图交互，`presentationBackgroundInteraction` 要 16.4）。
- [ ] 1.15 验证：审计用例改写为「展开 → 审计 → 点把手收起 → 面板上沿下移 >60pt、三个读屏元素仍在 → 审计 → 展开复原」，
      并逐项验红；真 key 构建由负责人目视拖把手的手感、减弱动态效果、VoiceOver 上下轻扫把手。
      - [x] 自动化：2026-09-24 iPhone 16 Pro `passed=24 failed=0`（审计 + XinghuoSnapshotTests + LowVisionChannelTests）；
            盲人端面板上沿 402.5 → 487.8（+85pt，屏高 874）。验红三项各自红过：把手点击置空 →「点把手没换档」；
            把手先画 →「把手排到了卡片内容前面」；收起态藏开关 →「收起后今日足迹开关不在了」。
      - [ ] 人工（**自动化够不着**）：`handleOffset` 的减弱动态效果分支、`accessibilityAdjustableAction` 上下轻扫
            （XCUITest 触发不了无障碍动作，记忆 `xcuitest-cannot-invoke-accessibility-actions`）、拖把手手感、
            志愿者端并排那一行（UI 用例只跑盲人端）、iPad。

### 1.16–1.17 第二轮（2026-09-24 负责人真机：「收起再省点高度」「收起和拖拉有明显卡顿」「定位按钮更小更透明」「今日足迹默认显示、不要开关」「整个面板压短，让地图占主导」）

- [x] 1.16 压缩：去掉足迹开关（足迹一律显示，加载失败仍有一行提示）；「演示数据」放在定位按钮那一行的左边
      （放标题后面时真机审计判标题 Text clipped，并排与拼成一个 Text 都试过），读屏走摘要句 hint；
      收起 = 一行「人数 + 行尾『听见星光』图标按钮」；展开 = 大数字降到 `.title`、内边距 12、间距 10；
      把手可见部分只留 20pt 一条，命中区（160 × 盲人 64 / 志愿者 44）往卡片上方伸；定位按钮看得见的部分 36pt 半透明，命中区不变。
      实测（iPhone 16 Pro，盲人端，卡片本体 = 里面的 ScrollView）：收起 **96pt**（上一版 292）；展开上沿 530（上一版 402）。
      用例上限：展开 ≤280、收起 ≤120；把手那条改回 64pt 时收起量得 140 → 红过。
- [ ] 1.17 卡顿：先插桩量（每秒掉帧数、整页重算次数、`updateUIView` 耗时，三种模式对照：正常 / 去毛玻璃 / 去星星动画），按证据修，修完负责人真机确认手感。
      - [x] 根因（2026-09-24 iPhone 真机日志）：不是渲染，也不是整页重算——掉帧基本为 0，`updateUIView` 每秒最多 55 次、共约 27ms；
            也没有手势被取消。是**一次拖动里位移归零 4–7 次**：把手随卡片 `offset`，而 `DragGesture` 按自身坐标算位移，
            形成反馈环（负责人原话「来回上下跳」），惯性预测一度算出 -2662pt，拖了不换档。修法：`coordinateSpace: .global`。
      - [x] 检查：用例加两次真拖（下拖 150 → 收起、上拖 150 → 展开）；改回自身坐标时报「往下拖 150pt 没收起」→ 红过。
      - [ ] 负责人真机确认手感。

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
