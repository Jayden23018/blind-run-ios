# 长红真机 UI 测试的送审影响归因（2026-09-27）

**问的是一件事**：TestFlight 外部测试的首个构建要过 Beta App Review，
`origin/main` 上这批「已知红灯」里，有没有**审核员能碰到的真缺陷**。
补的是 `testflight-readiness-20260927.md` §5 明确没覆盖的那一块。

**结论先说**：**11 条红灯里没有一条是审核员会碰到的阻断缺陷。**
5 条是用例陈旧或用例自身有缺陷，4 条是审计误报（其中 1 条是早已在代码注释里记过的启发式误报），
1 条是真缺陷（横屏下单页标题压在语音卡片上，只在横屏出现），1 条是没实测的疑似问题；
另记 2 条体验观察。都不阻断送审。
审核员最可能走的三条路径 —— **下单、删除账户、跑步中求助** —— 都在真机上实际走通了，证据见 §2。

## 0. 跑法与原始结果

- 代码：`origin/main` `b3b17ed`（本 worktree HEAD 与之逐字相同，工作区干净）
- 设备：iPhone 16 Pro / USB 有线（`devicectl` 的 `transportType=wired`）/ `scripts/device-test.sh`，统计只认 result bundle
- 范围：`blindRunUITests` target 的全部 3 个 suite，按 suite 分批（与 `device-test-all.sh` 的 UI 分批方式一致）
- ⚠️ **只跑了 iPhone，没跑 iPad**（记忆 `verified-on-one-device-is-not-verified`）

| suite | 结果 |
|---|---|
| `AccessibilityAuditTests` | `passed=35 failed=8 skipped=0 (total=43)` |
| `blindRunUITests` | `passed=36 failed=3 skipped=1 (total=40)` —— skip 的是 `testCloudBackendBlindRunnerBookingSmoke`（只在 Demo 构建跑，设计如此） |
| `blindRunUITestsLaunchTests` | `passed=1 failed=0 (total=1)` |

> 后两批第一次跑时因手机锁屏报了**零执行**（脚本硬失败，没有被当成通过）。解锁后重跑，上表是重跑的结果。

**与 PR #189（09-24）记录的 8 条对照**：
- 那 4 条流程失败里，**3 条已经不红了**：「有在途订单时冷启动没有直接进服务页」和两条「Volunteer home should show the assigned current order」，在 `b3b17ed` 上全部通过（陪跑员订单页 v2 系列 PR #212–#232 之后）。剩下 1 条「求助块没有打开求助中心」仍然红，见 §1 #3。
- 那 4 条审计失败（Contrast / Text clipped）**推断**对应下表 #5–#8。PR #189 没写用例名，只能按报警类型对，这一点无法逐字核实。
- 新出现的 5 条：两条响铃（PR #226 新增，**今天是第一次真机执行**）、两条记录 tab 审计（PR #191，09-24）、删除账户。下单冒烟在 09-17、09-19 的会话里已经红过，只是 PR #189 缩小后的范围没有覆盖它。

## 1. 逐条归因

失败签名都是 result bundle 里的原文。审计类的「被点名元素」取自日志里的 `[AUDIT]` 打印（`AccessibilityAuditTests.swift:1736`）。

| # | 用例 | 失败签名原文 | 归类 | 审核员会碰到吗 |
|---|---|---|---|---|
| 1 | `testAuthLifecycleBlindAccountDeletionIsTwoStageAndCompletesOnce` | `blindRunUITests.swift:1562: XCTAssertTrue failed` | **用例缺陷**：没滚动就点 | 不会。滑一下之后两段确认能走完，见 §2.1 |
| 2 | `testMockBlindRunnerBookingSmoke` | `blindRunUITests.swift:2385: XCTAssertTrue failed - Created booking should enter system dispatch status` | **用例陈旧**：文案 | 不会。订单确实建出来了 |
| 3 | `testMockBlindOrderHidesEmergencyActionInAcceptedStates` | `blindRunUITests.swift:1126: XCTAssertTrue failed - 求助块没有打开求助中心` | **用例陈旧**：控件类型 | 不会。求助中心确实打开了 |
| 4 | `testBlindBookingInLandscapePassesAccessibilityAudit` | `AccessibilityAuditTests.swift:1715: Contrast nearly passed`（`label=创建预约 frame=(403.0, 35.7, 67.7, 20.7)`） | **真缺陷**（只在横屏） | 只有把 iPhone 横过来进下单页才会碰到，见 §3.1 |
| 5 | `testBlindBookingPassesAccessibilityAudit` | `AccessibilityAuditTests.swift:1715: Text clipped`（`label=请听提示后说话 frame=(88.2, 317.3, 225.7, 40.7)`） | **疑似**，没在大字号下实测 | 默认字号下不会，见 §3.2 |
| 6 | `testBlindFirstRunHelpPassesAccessibilityAudit` | `AccessibilityAuditTests.swift:1715: Text clipped` ×2（被点名的是「怎么约跑」「怎么求助」两段的合成元素） | **审计误报**（已知） | 不会 |
| 7 | `testBlindOrderStatusInLandscapePassesAccessibilityAudit` | `AccessibilityAuditTests.swift:1715: Contrast failed`（`label=正在匹配陪跑员 frame=(324.2, 306.7, 225.7, 40.7)`） | **审计误报**：元素被固定栏压住 | 不会 |
| 8 | `testRunnerRecordsTabShowsMonthAndUnfinishedGroupAndPassesAudit` | `AccessibilityAuditTests.swift:1715: Dynamic Type font sizes are partially unsupported` ×4 | **审计误报**：List 行 | 不会 |
| 9 | `testVolunteerRecordsTabShowsMonthAndUnfinishedGroupAndPassesAudit` | 同上 ×5 | **审计误报**：List 行 | 不会 |
| 10 | `testRunnerRingOverlayHidesTheTabsAndStopsOnTap` | `AccessibilityAuditTests.swift:437: XCTAssertTrue failed - 注入了 RUNNER_RING，遮罩没出来` / `:438 … 遮罩期间标签栏还在读屏树里` / `:440 Failed to tap "runnerRingOverlay" … No matches found` | **用例缺陷**：用例自己把铃按停了 | 不会（审核员没有陪跑员账号，触发不了响铃） |
| 11 | `testRunnerRingOverlayEndsOnItsOwnAtUntil` | `AccessibilityAuditTests.swift:450: XCTAssertTrue failed - 注入了 RUNNER_RING，遮罩没出来` | 同 #10 | 同 #10 |

### #1 删除账户：触点落到了常驻求助条上

`blindRunUITests.swift:1559` 直接 `deleteButton.tap()`。失败时刻的界面结构：

```
Button, {{16.0, 761.3}, {370.0, 52.3}}, label: '删除账户'
Button, {{24.0, 723.0}, {354.0, 64.0}}, identifier: 'blindRunnerHomeSOSBar', label: '紧急呼叫，直接拨打电话'
TabBar, {{0.0, 791.0}, {402.0, 83.0}}
Sheet, label: '紧急呼叫'  →  拨打张三 / 拨打120 / 拨打110
```

触点落在求助条上，弹出的是本地拨号确认单，不是删除确认框。和 `ui-test-red-triage-20260822.md` 的 #6 是**同一种形态**，这次落在「我的」tab（09-16 起求助条挂在这一页，见 `AGENTS.md` §6）。
修法：点之前先 `swipeUp` 到底。§2.1 的实验已经验证过这样能过。

### #2 下单冒烟：等的是旧文案

`:2384` 等 `app.staticTexts["系统派单中"]`。失败时刻订单页已经在四步骨架的第 1 步：

```
Other, identifier: 'blindOrderFlowStatusCard', label: '正在匹配陪跑员。系统正在派单，请稍候。'
Button, identifier: 'blindOrderFlowLastRowButton', label: '取消匹配'
```

「系统派单中」仍存在于 `blindRun/Core/Models/OrderModels.swift`，但订单页 09-16 改版后已经不显示这几个字。
修法：改成等 `blindOrderFlowStatusCard`，按 identifier 断，别再抄中文文案。

### #3 求助中心：从系统 sheet 换成了自绘全屏层

`:1125` 按 `app.sheets["求助"]` 找。这条用例写于 `466b6d0`（09-15），那时求助中心是 `confirmationDialog`，XCUITest 把它认成 sheet。
同日 `fd4f0cc`（「求助与安全中心（五屏）」）把它换成了自绘的全屏层，理由见 `blindRun/Safety/SafetyHubView.swift:74` 的注释「为什么不是 `confirmationDialog`」。失败时刻的界面结构：

```
Other, identifier: 'blindSafetyHub'
  StaticText: '求助与安全, 跑步仍在记录, 还没有发送求助。请选择你现在要做的事。'
  Button #blindSafetyHubTriggerEmergency '一键求助'（按住 3 秒）
  联系志愿者 / 播报我的位置 / 问一句 / 拨打张三 / 拨打120 / 拨打110
```

**这条用例想守的红线本身是成立的**：打开求助中心时第一句说清「还没有发送求助」，逐字锁定的二次确认文案也没有被挪去当菜单正文。只是它从 `:1126` 起就走不下去了，**后面的二次确认断言自 09-15 起就没被执行过**。
修法：改成等 `blindSafetyHub`；后面的「一键求助 → 二次确认」按长按 3 秒或读屏双击的新交互重写。

### #6 首次使用帮助：已知的启发式误报

`blindRun/BlindRunner/BlindRunnerHelpView.swift:122-146` 的注释里已经写了 09-16 三次真机实测：被点名的是 `.accessibilityElement(children: .combine)` 合成出来的元素，`fixedSize` 改变不了它上报的几何；给「开始约跑」加 2 个字就能让这条审计从过翻成红。
页面本身是 `ScrollView`、没有高度约束。另一条用例 `testBlindFirstRunHelpAppearsOnFirstLaunchAndReturnsHome` 本轮**通过**：引导页出现 → 按「知道了」→ 回到首页。

### #7 横屏订单状态：被点名的元素在底部固定栏后面

失败截图里，横屏时订单页可滚动的内容区只剩 `y≈85–250`，被点名的「正在匹配陪跑员」（`y 306–347`）整个压在「求助与安全」固定栏下面。Element Screenshot 里只有那条栏的粉底和分隔线。
和 `AccessibilityAuditTests.swift:1707-1714` 已经放行的「陪跑员跑步页底部栏」**是同一类误报**。那段按几何放行的逻辑目前只认 `volunteerRunningBottomBar`，没认跑者端的 `blindOrderFlowSafetyHubButton`。

### #8 #9 记录 tab：List 行的字号审计误报

同一次运行里 `testRecordsTabScreenshotsInLightDarkAndLargestText` 拍下的 AX-XXXL 截图显示，被点名的「未完成的预约」「已取消」「2026 年 9 月 23 日 16:33」「朝阳公园南门」**全部明显放大**了。
判据与记忆 `list-rows-false-dynamic-type-audit` 一致：放大了就是误报，**不加白名单**。

### #10 #11 响铃：启动 helper 那一下点击把铃按停了

录像逐帧看：约 1 秒时还是「正在恢复账号资料」，约 2 秒时整屏遮罩「你的陪跑员到了 / 停止响铃」出现，约 3 秒时已经回到首页。离注入的 10 秒 `until` 还早。

根因在用例：`launchBlindHome` 在 `app.launch()` 之后固定点一下 `(0.5, 0.08)`，用来触发权限弹窗监视器（`AccessibilityAuditTests.swift:1854`）；而遮罩按设计是「点任意位置就停」（`blindRun/BlindRunner/RunnerRing.swift` 里 `RunnerRingOverlay` 的 `.onTapGesture(perform: onStop)`）。**用例自己把铃按停了**。
PR #226 的记录写着这两条「没有真机执行过」（当时 iPad 报 `Timed out while enabling automation mode`），今天是第一次跑。
修法：两条响铃用例别走带点击的 `launchBlindHome`，或者给它加一个「不点」的参数。

## 2. 审核员必经路径：本轮实际走通的证据

### 2.1 删除账户（App Review 指南 5.1.1(v)）

在 #1 的用例里**临时**加了「`swipeUp` ×2 → 等 2 秒 → 打印几何 → 再点」，只跑这一条：

```
[TRIAGE] before  delete=(16.0, 761.3, 370.0, 52.3) sos=(24.0, 723.0, 354.0, 64.0)
[TRIAGE] settled delete=(16.0, 709.3, 370.0, 52.3) sos=(24.0, 723.0, 354.0, 64.0)
[device-test] passed=1  failed=0  skipped=0  expectedFailures=0  (total=1)  result=Passed
```

滑动之后两段确认（「确认删除账户」→「最终确认删除账户」→ 回到登录页）完整走通。实验改动已 `git checkout` 还原，**没有提交**。

⚠️ 两个没完全解释清的地方如实记下：
- 停稳之后，无障碍树里「删除账户」的 frame（`709–761`）和求助条（`723–787`）**仍然重叠**，可点中心照样打开了删除确认框（第一次实验录像里滑动过程中的一帧，这一行也整个露在红条上方）。**无障碍 frame 与可见、可点区域不一致**，以实际点击结果为准。
- 第一次实验里，第一次读取 frame 后紧接着的硬断言失败了，第二次加了 2 秒等待，数值却完全相同。所以断言失败的原因是重叠判据本身（上一条），不是惯性回弹。

### 2.2 下单

#2 的失败现场就是证据：提交后订单页进入「匹配」步，状态卡「正在匹配陪跑员」，「取消匹配」按钮在。

### 2.3 跑步中求助

#3 的失败现场就是证据：`IN_PROGRESS` 时点「求助与安全」，求助中心打开，第一句是「还没有发送求助」。
**「一键求助 → 逐字锁定的二次确认」这一段本轮没有被任何用例执行到**，因为 #3 卡在它前面。不过审核员用 Mock 以外的账号到不了 `IN_PROGRESS`（需要真实陪跑员接单），这条对送审的暴露面很小。

## 3. 真缺陷 / 疑似 / 观察（按送审影响排序）

### 3.1 【真缺陷 · 低】横屏下单页，导航标题「创建预约」压在语音卡片上

`testBlindBookingInLandscapePassesAccessibilityAudit` 的失败截图里，inline 导航栏标题（`BlindBookingView.swift:1069` 的 `.navigationTitle("创建预约")`）是黑字，直接叠在蓝色语音卡片和麦克风图标上。Element Screenshot 就是黑字压蓝底。竖屏同一页正常：标题在卡片上方的导航栏里。
**审核员的路径**：登录跑者账号 → 首页「预约新的陪跑」→ 把 iPhone 横过来。可能性低，而且只是视觉问题，不影响功能。
同一张截图里，悬浮标签栏还压住了「重复一遍 / 改用表单」按钮的下沿（记忆 `tab-bar-clips-the-last-line-of-secondary-pages` 那一类）。

### 3.2 【疑似 · 低】下单页语音态大标题没加 `fixedSize`

`BlindBookingView.swift:1256` 的 `Text(voiceStageHeadline)`（`largeTitle`）没有 `.fixedSize(horizontal: false, vertical: true)`，紧挨着的 detail 文本（`:1261`）有。审计说的是「更大字号下**可能**被截断」。
**没有在 AX5 下实测**，默认字号下审核员碰不到。

### 3.3 【观察】「我的」tab 首屏看不到「退出登录」「删除账户」

刚进「我的」tab 时，这两行都在首屏以外（列表最后一个可见的是「关于」），被常驻「紧急呼叫」条和标签栏挡住，要往上滑才看得到。§2.1 已证明滑动后能走通。
对 5.1.1(v)「易于找到」的风险低：设置页底部是删除入口的常见位置。但如果审核员没滑、直接点那一截红条，弹出的会是「紧急呼叫」拨号单，第二下才会真的拨出去。

### 3.4 【观察】iPhone 横屏下订单页可滚内容只剩约 165pt

见 #7 截图：导航栏、四步进度、底部「求助与安全」和标签栏各占一截，中间可滚区域约 `y 85–250`。不是缺陷，是横屏布局的密度问题，记下来备查。

## 4. 这批红灯的共同形态

- **「没滚动就点，点到了常驻求助条」这是第二次**（08-22 的 #6 在盲人首页，这次在「我的」tab）。按 `AGENTS.md` §1 归档进项目记忆 `ui-test-tap-lands-on-persistent-sos-bar`。
- **用例找的是控件类型或中文文案，不是 identifier**（#2 `staticTexts["系统派单中"]`、#3 `sheets["求助"]`）。08-22 那份 §4 提过的静态闸只抓 identifier，抓不到这两种。
- **新用例合进 main 时从没真机跑过**（#10 #11，PR #226 自己写明了）。这是记忆 `merged-prs-whose-tests-never-ran` 的又一例。

## 5. 复现

```bash
# 分 suite 跑（本仓库 worktree 需先把主 checkout 的 Pods 软链过来，两边 Podfile.lock 要逐字节相同）
ln -s /Users/mac/Downloads/blind-run-ios/Pods Pods
for s in AccessibilityAuditTests blindRunUITests blindRunUITestsLaunchTests; do
  AIDRUN_PREFLIGHT_TIMEOUT=900 scripts/device-test.sh -only-testing:blindRunUITests/$s
done

# 审计被点名元素：日志里 grep [AUDIT]
# 失败时刻界面结构 / 录像：<bundle 目录>/attachments/manifest.json（device-test.sh 自动导出）
```
