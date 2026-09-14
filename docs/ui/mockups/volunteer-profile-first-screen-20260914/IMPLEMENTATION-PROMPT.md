# 执行 prompt：把志愿者「我」首屏方案 A 落地

> 这份文件是给**新 session** 用的自足 prompt。整份复制粘贴即可，不需要上一轮会话的任何上下文。
> 设计决策已定，不要重新讨论方案；**实现方式没定，必须先查清楚再动手**。

---

## 复制以下全部内容作为新 session 的第一条消息

把 AidRun 志愿者端首屏改成「个人身份 / 影响力」优先的一屏（设计方案已定稿，代号方案 A）。

**启动方式**：`claude --add-dir /Users/mac/Downloads/demo`（需要读后端契约）
**工作目录**：`/Users/mac/Downloads/blind-run-ios`

### 零、开工纪律（这几条比需求本身重要）

1. **先 `Shift+Tab` 进 plan mode**，状态栏要显示 `⏸ plan mode on`。探索阶段只读不改。
   出计划 → 列会改哪些文件 → 说风险 → **停下来等我批**。我没说「开始」就不要写代码。
2. **任何不确定的地方，先把代码读到确定再动手**。禁止出现「应该是」「一般来说」「我记得」。
   函数签名、行号、某个字段存不存在 —— 自己读，或派 subagent 核，不要推测。
3. **每改一处都要有能跑的检查**，改完主动跑并把真实输出贴出来。没跑就明说没跑。
   禁用「应该没问题」「理论上可以」。`passed=0` 一律当失败查。
4. **不许偷懒**：不要只改能编译过的部分就宣称做完；不要跳过难的那一半；
   范围内的每一项都要做完，做不完的明说哪项没做、为什么。
5. **写完之后派 subagent 做 code review**（跑内置 `/code-review`，它在全新 subagent 里只看 diff）。
   给它这份 prompt 让它逐条对照查漏，并查有没有改到范围外的东西。
   ⚠️ reviewer 一定能找出问题，让它**全报**并自分两档：A = 影响正确性或违反本 prompt 的（必修）/
   B = 其余（默认不动）。我只按 A 动手。**不要写「只报高危」「保守一点」**。
6. 探索/定位/读日志可以派 subagent（用 haiku 或 sonnet）；**设计取舍和写码自己干**。
   **改任何文件前自己完整读一遍那个文件** —— 探索可以外包，编辑不行。
   ⛔ 不要让 subagent 跑测试（挂了你需要完整输出去诊断，它只会回「3 tests failed」）。

### 一、先读这些（按顺序，别跳）

1. `AGENTS.md`（仓库根，最高优先级工作契约）——尤其 §1 事故复盘规则、§8 iOS 硬规则、
   §9 冻结文件、§10 工作流、§11 验证命令
2. `CONTEXT.md`（仓库根）—— 领域词 ↔ 模块名对照表。**在写下「这个功能仓库里没有」之前必读一次**，
   换一组同义词再搜
3. 设计稿与依据（本 PR 已合入 main）：
   - `docs/ui/mockups/volunteer-profile-first-screen-20260914/README.md` —— 逐字段来源表 + 两条实现约束
   - `docs/ui/mockups/volunteer-profile-first-screen-20260914/01-final-screen.html` —— 用浏览器打开看
   - `docs/ui/mockups/volunteer-profile-first-screen-20260914/00-three-directions.html` —— 方案 A 在最左列
   - `docs/research/volunteer-profile-first-screen-20260914.md` —— 外部依据（Strava 版式、Uber Base 滑动按钮原文规格）
   - `docs/research/volunteer-home-incentive-layer-20260914.md` §3 —— **三条必须反着做的**，是硬约束不是建议
4. `docs/ui/ui-review-checklist.md` —— 收尾要逐项过

### 二、已定的设计（不要重新讨论）

从上到下：**紧凑身份行 → 主指标 → 3 列统计 → 星级进度 → 徽章一排 → 最近陪跑 → 底部滑动 CTA**。
主指标与次级数字差约 3× 字号；一屏只强调一个主指标。

**每个数字的真实来源（已核实存在，不要自己造字段）**：

| 稿上位置 | 字段 | 端点 |
|---|---|---|
| `24 次陪跑`（主指标） | `totalCompleted` | `GET /api/volunteer/achievements` |
| `186 小时` | `totalServiceMinutes` / 60 | 同上 |
| `8 位 固定搭档` | `volunteerFavoritedBy().count` | `GET /api/volunteer/favorites` |
| `4.9 · 32 条` | `avgRating` / `totalRatings` | `GET /api/volunteer/achievements` |
| `三星 186/300 小时` | `starLevel.current` / `currentHours` / `nextTarget` | 同上 |
| 已解锁徽章 | `badges[]`（**只含已解锁**） | 同上 |
| `夜跑守护 3/5` | `nextBadge.name` / `current` / `target`（全解锁时为 `null`） | 同上 |
| 最近陪跑 | `createdAt` / `blindName` / `startAddress` / `status` | `VolunteerServiceRecord` |

相关代码位置（**落笔前自己再核一眼行号，可能已漂移**）：
`blindRun/Volunteer/VolunteerAchievements.swift`（`VolunteerAchievementsResponse` / `VolunteerBadgeDto` /
`VolunteerNextBadgeDto` / `VolunteerStarLevelDto`）、
`blindRun/Volunteer/VolunteerHomeIncentive.swift` 与 `VolunteerHomeIncentiveView.swift`、
`blindRun/Core/Services/IncentiveService.swift`（三条路径字面量）、
`blindRun/Volunteer/VolunteerOrderFlowViews.swift`（`VolunteerServiceRecord` / `VolunteerServiceRecordRow` /
`VolunteerServiceRecordsView` / `VolunteerServiceRecognitionView` / `VolunteerBadgeWallView`）、
`blindRun/Volunteer/VolunteerHomeView.swift`（**2524 行**，`VolunteerHomeViewModel` 在 25，
`VolunteerHomeView` 在 1224）。

⛔ **三样刻意不做，不要在实现时"顺手补上"**（理由见调研报告 §4）：
- **累计里程 / 陪伴总距离** —— 后端 spec 逐字写「刻意没有」（跨订单求和会把 OOM 风险搬进成就页）。
  单单粒度的 `TrackStats.distanceMeters` 存在，但跨订单求和正是后端拒绝的那件事
- **「本月 N/M 次」月度目标、同比涨跌、「还差 1 单就…」** —— Moving Target 红线
- **服务时长折算成金额** —— 网信办 2026-06-19 通知 + 民政部令第 67 号

⛔ **「证明 / 证书」字样不得出现** —— `/api/volunteer/achievements` 的 description 明令。

**配色**：全部取自 `blindRun/Core/DesignSystem/AppColors.swift`，**不新增颜色**。
暖底用中性暖色（背景色不承载文字对比度义务）。不要引入 Strava 品牌橙 `#FC5200`
（压白底约 3.1:1，过不了 `AppColorContrastTests` 的 4.5:1）。

### 三、滑动 CTA（这条最容易做错）

依据是 Uber Base Design System 的 Sliding button 规格（原文在调研报告 §3）：

- **它绑的是 `setAvailability(true)`，不是导航**。它替代现有那个 `Toggle`
  （`VolunteerHomeView.swift` 里 `isOn: $isAvailable` 那处）。
  官方 Caution 逐字写着「动作不关键时，滑动只是徒增复杂度」——
  只有绑在「开始真的收派单」这个有后果的动作上，滑动才立得住
- **阈值取 Low (Easy) = 滑过 20% 触发**（官方警告高阈值对运动障碍者与老年人不友好）
- **必须给辅助技术留一个标准 action**，不能只有裸拖拽手势 —— VoiceOver / Switch Control /
  Voice Control 用户可能根本不触碰屏幕。这条**必须有测试钉住**
- 单个箭头图标；滑块高度 == 底条高度；高对比度主色底
- 🔴 **摩擦力只加在「开启」一侧**：关闭是普通点按，**不得弹任何激励挽留**。
  这条已经以注释钉在 `blindRun/Volunteer/VolunteerHomeIncentive.swift:100` 附近，别绕过去
- 控件名的单一来源是 `VolunteerHomeView.swift:16` 的 `VolunteerAvailabilityCopy.toggleTitle = "可服务开关"`，
  别自己起第二个名字

### 四、必须在 plan mode 里想清楚再问我的三件事

设计只定了「第一屏长什么样」，下面三件**没定**，不要自己挑一个闷头做：

1. **地图 / 派单面板去哪了？** 现在 `VolunteerHomeView` 是「地图铺满 + 底部面板」的叠层结构。
   方案 A 把第一屏换成个人页后，原来那一整套（`homeMap` / `nearbyDemandPanel` /
   `recenterButton` / detent 抓手）是变成 push 的二级页、sheet、还是 tab？
2. **派单弹窗 `VolunteerDispatchOverlay` 怎么办？** 它现在挂在 `VolunteerHomeView` 的 `.overlay`。
   如果志愿者正停在个人页而派单推送到了，**弹窗必须照样出现** —— 这是模态最高优先级，
   不能因为换了首屏就丢掉
3. **`VolunteerScheduledOrdersSection`（我的预约 / 临期确认）放哪？**
   `volunteer-scheduled-order-confirm-ui-20260906.md` 的结论是「入口一律独立于『当前进行中』那个位」，
   且确认按钮要直接摆在预约卡上、不进溢出菜单不进二级页。新首屏里它没有位置，这是真缺口

顺带确认一下：现有底部三个入口（记录 / 成就 / 设置）在新设计里被吸收了
（最近陪跑「全部 ›」→ 服务记录页，徽章「全部 ›」→ 成就页，齿轮 → 设置页）。
请核对这三条跳转的目标是否与现有页面一致，并在计划里说明 `bottomEntries` 是删还是留。

### 五、这个仓库已知的坑（都真实发生过，别再踩一遍）

- 🔴 **`.task` 挂在「条件不成立就不显示」的空视图上不会触发** —— 数据永远不加载、永远渲染空，
  自己锁死自己且零报错。上一个 commit（`a3cee29`）修的就是这个。
  新首屏全是条件卡片，**这是最可能复发的一条**。判据：问「数据没到那一刻渲染树里有没有东西」
- **单测绕过视图层**：view model 的单测全绿也证明不了视图渲染了。本仓库 CI 跑不了 XCTest，
  UI 测试是唯一能看见这一层的通道
- **容器上的 `accessibilityIdentifier` 会向下覆盖子元素的 id**，要配 `children: .contain`
- **SwiftUI 遍历顺序 = 绘制顺序**，`accessibilitySortPriority` 跨叠放层是空操作。
  装饰性元素只能 `accessibilityHidden(true)`，且必须加在元素被合成的那一层
- **`List` 不渲染屏幕外的行**，UI 测试断言前要先滚动；`ScrollView` 屏幕外子视图**照样**
  `isHittable == true`（两种坑不一样，后者用 `scrollElementIntoView`）
- **「失败时在列表末尾多出一行字」等于没有反馈** —— 字号最大、列表最长时那一行在不在第一屏？
  失败分支的断言要打在弹窗出现上
- **`BlindBookingViewModel` 一类的 view model 依赖是 `weak`**，单测里传临时对象等于传 nil
- **UI 测试 launch argument 打错名字会静默通过**（App 以默认状态启动，截图逐像素相同，照报 passed=1）
- 部署目标是 **iOS 16**，不要用更新的 API。`swiftui-pro` skill 里写的「iOS 26 默认」「Swift 6.2」**不适用**

### 六、验证（AGENTS.md §11）

- **CI 跑不了任何 XCTest**（高德 SDK 没有 arm64-sim slice，模拟器通道永久不可用）。
  单测与 UI 测试**一律真机本地跑**：`scripts/device-test.sh`
- **默认不要裸跑全量**（约 10 分钟，会超 Bash 600s 上限）。先按改动涉及的符号搜
  `blindRunTests/` 定范围，只跑命中的 suite：
  `scripts/device-test.sh -only-testing:blindRunTests/XxxTests`
  只有改到「全 App 唯一出口 / 共享单例 / 全局配置」才必须全量
- 命令行跑测试要显式传 `DEVELOPMENT_TEAM=ZW39BS8NXT`
- **零执行不是通过**：`passed=0 failed=0` 一律当失败查
- **「真机验过」默认只验了 iPhone**。这次是布局几何类改动，**必须两台**
  （`111` 与 `iPad Pro (2)`，`scripts/dual-device-validation.sh`），或在 PR 里说清只验了哪台
- 真机跑不起来时按**错误签名**分诊，大多不是代码问题（`signal kill` 就原样复跑一次比失败用例名，
  两次失败集合零重叠就不是代码）。**别去查签名 / SPM 依赖**

### 七、冻结与边界

- **`Podfile` 整文件冻结**
- `blindRun.xcodeproj/project.pbxproj` 可以改，但**不得触及 `DEVELOPMENT_TEAM`**
- 任何构建文件**不得写入 `EXCLUDED_ARCHS`**
- 新增 `.swift` 文件**不需要**改 pbxproj
- 这是纯 iOS 前端仓库，**不要加服务端代码**；接口契约的唯一源在后端仓库，本仓库不改契约
- 文案避开「接单 / 订单 / 抢单 / 待接订单」这类交易语气（AGENTS.md §15）

### 八、收尾

1. 跑测试、贴真实输出
2. 派 subagent 跑 `/code-review`（见第零节第 5 条）
3. 过 `docs/ui/ui-review-checklist.md`
4. 需要后端拍板的问题投 `/Users/mac/Downloads/demo/docs/handoff.md` 的「待后端确认」
   （只读末尾 `tail -80`，不要整读，文件近万行）
5. commit（`type: 描述`，**不带 Co-Authored-By**）→ push → 开 PR 到 `main`
6. `gh` 命令一律显式带 `--repo Jayden23018/blind-run-ios`（裸跑会打到 upstream，返回另一个仓库的列表）

**范围提醒**：这是一次跨多文件的结构性改动。如果你判断一次做完风险太大，
在 plan mode 里提出分期方案让我批 —— **但不要自己悄悄缩小范围**，缩不缩是我的决定。
