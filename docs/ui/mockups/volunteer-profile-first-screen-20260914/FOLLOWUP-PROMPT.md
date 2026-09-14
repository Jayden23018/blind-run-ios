# 执行 prompt：志愿者首屏的三条返工（删工作台 / 显眼的培训入口 / 滑动后跳转）

> 给**新 session** 用的自足 prompt。整份复制粘贴即可，不需要上一轮会话的任何上下文。
> 起因是用户看了真机之后提的三条意见，**其中一条刻意留到设计稿出来再做**。

---

## 复制以下全部内容作为新 session 的第一条消息

继续做 AidRun 志愿者端首屏。上一轮把首屏改成了「个人身份 / 影响力优先」的一屏
（PR #136，**还开着没合**），用户在真机上看完提了三条返工意见。

**启动方式**：`claude --add-dir /Users/mac/Downloads/demo`（需要读后端契约）
**工作目录**：`/Users/mac/Downloads/blind-run-ios`
**分支**：`feat/volunteer-profile-first-screen`（**继续在这条上做，不要新开**——
同一块屏幕的返工属于同一件事，合之前不该让 main 上出现半个方案）

### 零、开工纪律（这几条比需求本身重要）

1. **先 `Shift+Tab` 进 plan mode**，状态栏要显示 `⏸ plan mode on`。探索阶段只读不改。
   出计划 → 列会改哪些文件 → 说风险 → **停下来等我批**。我没说「开始」就不要写代码。
2. **任何不确定的地方，先把代码读到确定再动手**。禁止出现「应该是」「一般来说」「我记得」。
   函数签名、行号、某个字段存不存在 —— 自己读，或派 subagent 核，不要推测。
3. **架构上的取舍不确定时，停下来问我**，不要自己挑一个闷头做。
4. **每改一处都要有能跑的检查**，改完主动跑并把真实输出贴出来。没跑就明说没跑。
   禁用「应该没问题」「理论上可以」。`passed=0` 一律当失败查。
5. **报错要一条条看完再动手**，不要看到第一条就开始改 —— 这个仓库的编译错误常常是
   同一个根因扇出几十条（删一个类型会让测试文件报十几条 `cannot find ... in scope`）。
6. **不许偷懒**：不要只改能编译过的部分就宣称做完；范围内的每一项都要做完，
   做不完的明说哪项没做、为什么。
7. **写完之后派独立 subagent 做 code review**（全新上下文，只看 diff）。
   给它这份 prompt 让它逐条对照查漏，并查有没有改到范围外的东西。
   ⚠️ reviewer 一定能找出问题，让它**全报**并自分两档：A = 影响正确性或违反本 prompt 的（必修）/
   B = 其余（默认不动）。**不要写「只报高危」「保守一点」** —— 官方文档点名这种写法会让模型真的少找。

### 一、先读这些（按顺序，别跳）

1. `AGENTS.md`（仓库根）—— 尤其 §1 事故复盘规则、§8 iOS 硬规则、§9 冻结文件、§11 验证命令
2. `CONTEXT.md`（仓库根）—— 领域词 ↔ 模块名对照表。**在写下「这个功能仓库里没有」之前必读一次**
3. `git log --oneline origin/main..HEAD` 看上一轮做了什么（4 个提交），
   然后 `git diff origin/main...HEAD --stat`
4. `docs/ui/mockups/volunteer-profile-first-screen-20260914/README.md` 与 `01-final-screen.html`
5. `docs/research/volunteer-home-incentive-layer-20260914.md` §3 —— **三条必须反着做的**，是硬约束不是建议

### 二、这一轮要做的三件事

#### ① 删掉「派单工作台」二级页

用户原话：**「现在这个派单工作台好像是没什么用的，不需要这个派单工作台」**。

删 `VolunteerDispatchWorkbenchView`（在 `blindRun/Volunteer/VolunteerHomeView.swift`）、
删首屏上那行 `volunteerProfileWorkbenchEntry` 入口。

**里面的东西要有去处，逐个交代，不许静默丢掉**：

| 现在在工作台里 | 去哪 |
|---|---|
| 辅助地图 `volunteerHomeMap` + 「回到当前位置」 | **删掉**（见下面 ②） |
| `VolunteerDispatchSummaryCard`（覆盖范围 / 派单·接受·拒绝·超时四计数） | 搬回首屏 |
| 「去培训」按钮 | 搬回首屏，**并且要显眼**（见下面 ③） |
| `VolunteerCertificateUploadEntryLink`（`notAvailableReasons` 含 `.notVerified` 时） | 搬回首屏作业区 |
| 定位摘要文字 / `#if DEBUG` 诊断与 `DebugTestingPanel` | 搬回首屏 |

#### ② 删掉那张辅助地图

它的 `annotations` 恒为 `[]`，唯一信息是「我在哪」，而覆盖范围文字在派单状态卡里已经有一份。
连带删 `recenterButton` 与 `recenterToken`。

⚠️ **但不要连定位一起删**：`locationService.requestPermission()` / `startUpdating()` 是派单的前提，
`VolunteerHomeView.onAppear` 里那两行必须留着。删地图 ≠ 停定位。

#### ③ 必修培训的入口要显眼，且直接可达

用户原话：**「必须在派单工作台点进去再点击一个贼小的去培训，一点都不显眼」**。

要做成：**首屏上「尚未完成必修培训」本身就是一个大的可点入口，点一下直接进培训页**，
不是「一行说明 + 旁边一个小链接」。

- 判据沿用既有的：`summary.notAvailableReasons?.contains(.trainingIncomplete)`
- 目标页沿用既有的 `VolunteerTrainingView()`（现在用 `.sheet` 包一层 `NavigationStack` 打开）
- 🚩 **注意一个既有的坑**：`needsTrainingEntry` 读的是 `dispatchSummary`，
  而派单摘要拉失败时 `dispatchSummary` 为 nil ⇒ 这个入口整块消失。
  志愿者此刻看到的是「派单状态待同步」，而真实原因可能就是他没做培训。
  **这一轮请判一下要不要兜**，不确定就问我。

### 三、这一轮**不做**的那件事（重要）

用户还提了第三条：**「滑动了开始跑步之后，应该跳转到另一个界面，而不是停在同一个界面」**。

**这条本轮不做** —— 用户明确说了「完全新设计，我先出设计稿」，那一屏（暂称「等待派单」页）
的版式还没定。本轮只做上面①②③。

但请在 plan mode 里**顺带回答一个问题**给我确认：删掉工作台之后，
`VolunteerDispatchSummaryCard` 那一块暂时放首屏哪个位置，等「等待派单」页出来时
搬起来代价最小？（我要的是「别把它焊死在首屏中间」这个取舍，不是完整方案。）

⛔ **不要自己发明一个「等待派单」页**。不要自己画那一屏。

### 四、这一轮不许碰的（上一轮刚定下来的，别顺手改回去）

- **滑动 CTA 的阈值 20%**（Uber Base Low/Easy；高阈值对运动障碍者与老年人不友好），
  以及它的 `accessibilityRepresentation`（辅助技术拿到一枚普通按钮）
- 🔴 **摩擦力只加在「开启」一侧**：关闭是普通点按，**不得弹任何挽留或二次确认**
- **培训没完成时不拦住滑动**（用户已确认）：开关照常能开，只是后端暂不派单给他
- 「我的预约」`VolunteerScheduledOrdersSection` + 「当前订单卡」**必须留在首屏**，
  且排在影响力区**之前**（带 60 分钟到期的动作，读屏顺序播报、排序就是优先级）
- 派单弹窗 `VolunteerDispatchOverlay` 挂在 `NavigationStack` **外面**（否则 push 出二级页会被盖住）
- `AppColors.availabilityOnSurfaceTone`（「已开启」绿底，暗色白字 8.11:1）——
  别改回 `AppColors.success`，那个暗色值压白字只有 2.02:1
- 「最近陪跑」那一行**不显示积分**（积分与服务时长刻意分两屏，中央网信办 2026-06-19 通知第 2 条）

### 五、这个仓库已知的坑（都真实发生过）

- 🔴 **`.task` 挂在「条件不成立就不显示」的空视图上不会触发** —— 数据永远不加载、永远渲染空，
  自己锁死自己且零报错（commit `a3cee29` / PR #134 修的就是这个）。
  首屏的 `.task` 现在挂在一棵永远非空的子树上，**搬动结构时别把它挂回条件分支里**。
  判据：问「数据没到那一刻渲染树里有没有东西」。
- **XCUITest 的 `tap()` 够不着 accessibility action**：它注入的是物理触摸，
  不经过 `accessibilityRepresentation` / `accessibilityAction`。
  别写「tap 那枚无障碍按钮 → 断言状态变了」，那是一条必红且红得毫无信息量的用例。
  详见 `AGENTS.md` §1.4 索引里那条。
- **容器上的 `accessibilityIdentifier` / `accessibilityLabel` 会向下覆盖子元素**，要配 `children: .contain`；
  可点按钮塞进 `.accessibilityElement(children: .combine)` 里会点不到。
- **`List` 不渲染屏幕外的行**；**`ScrollView` 屏幕外子视图照样 `isHittable == true`**
  （两种坑不一样，后者要 `scrollElementIntoView`，本仓库 2026-08-14 因此差点拨出 110）。
- **「失败时在列表末尾多出一行字」等于没有反馈** —— 字号最大、列表最长时那一行在不在第一屏？
- **view model 依赖是 `weak`**，单测里传临时对象等于传 nil（守卫规则 `weak-temporary`）。
- 部署目标是 **iOS 16**，不要用更新的 API。
- **固定磅值字号不跟 Dynamic Type 走** —— 本仓库为这条栽过（成就页头部曾写死 48pt）。
- **CI 跑不了任何 XCTest**，UI 测试是唯一能看见视图层的通道。

### 六、验证

- 单测与 UI 测试**一律真机本地跑**：`scripts/device-test.sh`（会先探活、锁屏立即失败）
- **默认不要裸跑全量**（约 10 分钟，会超 Bash 600s 上限）。按改动涉及的符号搜 `blindRunTests/`
  定范围，只跑命中的 suite：`scripts/device-test.sh -only-testing:blindRunTests/XxxTests`
- **删掉工作台会让这些用例红，必须跟着改**（改之前先自己 grep 一遍确认清单）：
  `volunteerProfileWorkbenchEntry` / `volunteerHomeMap` / `volunteerDispatchWorkbench` /
  `回到当前位置` / `接单率` 这几个 key 在 `blindRunUITests/blindRunUITests.swift` 里的引用。
  守卫 `stale-ui-test-identifier` 会双向拦住漂移，但**它拦不住中文文案断言**。
- **零执行不是通过**：`passed=0 failed=0` 一律当失败查
- **这是布局几何类改动**，理想是两台（`111` 与 `iPad Pro (2)`）。
  iPad 上一轮全程离线 —— 跑不到就在 PR 里写清只验了哪台，**不要假装验过**

### 七、上一轮留下的两笔账（不是你造成的，但你会撞上）

1. **`blindRunTests/LowVisionChannelTests.testAvailabilityOnSurfaceKeepsWhiteTextReadable`
   这条新用例还没在真机跑过**（设备中途掉线）。你这轮第一次跑测时顺带把它跑了。
2. **`origin/main` 基线上本来就有 6 条红的**，不是本次回归，别去修也别当成自己弄坏的：
   - `AccessibilityAuditTests`：`testBlindBookingPassesAccessibilityAudit`（Text clipped）、
     `testBlindFirstRunHelpPassesAccessibilityAudit`（Text clipped）、
     `testBlindOrderStatusInLandscapePassesAccessibilityAudit`（Contrast failed）、
     `testBlindBookingInLandscapePassesAccessibilityAudit`（Contrast nearly passed）
   - `blindRunUITests`：`testAuthLifecycleVolunteerDeletionRouteAndActiveOrderBlock`（找不到「删除账户」）、
     `testMockBlindRunnerBookingSmoke`（提交按钮未启用）

   ⚠️ 红着的用例会把后来引入的失败一起吃掉（`continueAfterFailure = true`）。
   判回归**只能比失败签名，不能比失败条数**。

### 八、冻结与边界

- **`Podfile` 整文件冻结**；`project.pbxproj` 可以改但**不得触及 `DEVELOPMENT_TEAM`**；
  任何构建文件**不得写入 `EXCLUDED_ARCHS`**
- 新增 `.swift` 文件**不需要**改 pbxproj
- 纯 iOS 前端仓库，**不要加服务端代码**；接口契约的唯一源在后端仓库，本仓库不改契约
- 命令行跑测试要显式传 `DEVELOPMENT_TEAM=ZW39BS8NXT`

### 九、收尾

1. 跑测试、贴真实输出
2. 派独立 subagent 跑 code review（见第零节第 7 条）
3. 过 `docs/ui/ui-review-checklist.md`
4. 需要后端拍板的问题投 `/Users/mac/Downloads/demo/docs/handoff.md` 的「待后端确认」
   （只读末尾 `tail -80`，不要整读，文件近万行）
5. commit（`type: 描述`，**不带 Co-Authored-By**）→ push → **更新 PR #136 的描述**（不是新开 PR）
6. `gh` 命令一律显式带 `--repo Jayden23018/blind-run-ios`（裸跑会打到 upstream，返回另一个仓库的列表）
