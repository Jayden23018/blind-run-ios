# STATE — 视障跑者端首页 + 单页订单流程（2026-09-16）

分支 `feat/blind-runner-home-and-single-page-order-flow` · **PR #141（draft）** · 8 个 commit

设计稿在 `/Users/mac/Downloads/zhumangpao-ios-order-flow-handoff/design-reference/order-flow/`
（**精确数值以 `home.html` / `prototype.html` 的 CSS 为准**，截图只是它们的渲染）。
原始需求在同目录上一层的 `PROMPT.md`。

---

## 总体决策（已与项目负责人逐条确认，**不要重新讨论**）

1. **首页底部常驻求助条删除**，紧急入口改由「我的」tab 底部兜底。`AGENTS.md` §6 与
   `docs/05-page-specs.md` 已改口径**并写明代价**：不开读屏的低视力用户在首页够不到它。
   magic tap 手势保留并上移到标签栏容器（三个 tab 都生效），两个确认弹窗随之上移。
2. **「重复当前状态」** 首页 = 问候行右侧一枚 64pt 图标；订单页 = 导航栏右侧同款图标。
   **必须是可见按钮**，不许做成 accessibility custom action。
   ⚠️ **三处都已落地**（首页 `greetingRow`、订单页 toolbar、执行屏），**不要再往求助中心加第四个**
   —— 详见下面「本轮否掉的」。
3. **「继续等待」** `PENDING_MATCH` 删、`REMATCHING` 保留。判据 `offersBlindRunnerKeepWaitingControl`。
4. **底部标签栏**（首页 / 记录 / 我的），三个 tab 全挂已有页面。
5. **暗色槽位按现有体系推导并跑用例验证**，不加 `.preferredColorScheme(.light)`。

---

## 阶段进度

- [x] **阶段 1** 设计 token + 通用组件 — `abe4cd6`，真机 `passed=23 failed=0`
- [x] **阶段 2** 首页 + 标签栏 — `2112a72`，真机 UI `passed=21 failed=3`（剩 3 条为既有）
- [x] review 修复 11 条 A 档 — `5f4557d`
- [x] 引导页 fixedSize + 三跑实测记录 — `12f41ca`
- [x] **阶段 3a** 订单页四态骨架（静态布局）— `5e404e3`，**真机零执行**
- [x] **阶段 3b** — `7c726dc` + review 修复 `676ebdb` + 真机首跑修复 `a9c7cc6`，
      **真机已验**：单测 `1204/0`、UI `21/4`（4 条里 3 条既有 + 1 条待查，见下）
- [ ] 阶段 4 过渡动画
- [ ] 阶段 5 VoiceOver / 动态字体 / 减弱动态效果 / 触感

---

## ✅ 真机验证已跑（2026-09-16，iPhone 16 Pro 有线）

**全量单测 `passed=1204 failed=0`**（`scripts/device-test.sh -only-testing:blindRunTests`）。
按 AGENTS §11 走全量而不是按符号收窄 —— 本轮改了 `EmergencyDialer.telURL`，
那是全 App 唯一的拨号出口。

**UI 套件 `passed=21 failed=4`**（`-only-testing:blindRunUITests/AccessibilityAuditTests`）。
本轮新增的两条 UI 用例全绿。4 条失败里 **3 条签名与下面「已知既有 3 条红」逐条吻合**。

跑出来的三件都是真缺陷，已修（`a9c7cc6`）：

1. **`EmergencyDialer.telURL` 拦不住掩码串** —— `138****1234` 拼得出 `tel://1381234`，
   一个七位的、可能真打给别人的号码。**AGENTS.md §8 与 `ui-review-checklist.md` 原来写的
   「会拨成空号」是错的**，而那句错话正是这道闸一直没加的原因（让人以为「只取数字位」
   已经兜住了）。现在显式拦 `*` / `＊`，15 个调用点一次覆盖；误报面（带空格横线的明文号、
   110/120 三位号）双向钉住。
2. **横屏订单页布局塌了**（3a 无意引入）：`debugMockControls` 挂成了
   `BlindOrderFlowView` 的兄弟节点而不是放在 ScrollView 里 ⇒ 横屏 390pt 高度下
   状态标题、副标题、四行信息一个字都看不到。放回 footer 即恢复。
3. **`Button(role: .cancel)` 不在元素树里**（iOS 26 实测）：`confirmationDialog` 渲染成
   `Popover`，`不取消` 被系统换成 `identifier: 'PopoverDismissRegion', label: 'dismiss popup'`
   —— **英文 label**，而那是一个中文破坏性二次确认唯一的退出口。系统给的，已记进交接。

### ⏭ 唯一还红的一条：`testBlindOrderStatusInLandscapePassesAccessibilityAudit`

2 条 `Contrast failed`。布局修复前后都红，但内容已从「看不到」变成「要滚动」。
**逐个量过声明值，全部过线**：

| 配对 | 实测 | 需要 |
|---|---|---|
| `helpText #B42318` 压 `helpBackground #FDECEC` | 5.76:1 | 4.5 ✅ |
| `helpStroke #C25A4E` 压 `helpBackground` | 3.78:1 | 3.0 ✅ |
| `helpStroke` 压页面底 `#F4F4F8` | 3.93:1 | 3.0 ✅ |
| 标签栏未选中 `#212121` 压 `#FDFDFD` | 15.83:1 | 4.5 ✅ |
| 标签栏选中 `#0B2251` 压药丸 `#EFEFEF` | 13.41:1 | 4.5 ✅ |
| **实测抗锯齿混合色 `#CD6F5F` 压 `#FDEFEF`** | **3.11:1** | 4.5 ❌ |

⇒ 唯一不过线的是 **1.5pt 描边的抗锯齿边缘像素**，不是调色板里任何一个值。
取色方法（可复现）：从 result bundle 的 `Element Screenshot` 直方图取主色，
`swift /tmp/px.swift <png>`（脚本见该 commit 的提交信息）。
**已分出独立任务**，不在阶段 3b 里改调色板 —— 要么把描边加粗/换色让边缘像素也过线，
要么确认是 audit 对细描边的系统性行为后按 `auditIgnoredIdentifiers` 显式豁免。
⛔ 别直接加豁免了事：那等于用绿灯替一个没查清的问题背书。

---

## 历史：跑之前的那轮零执行清单（留档，已作废）

**必须插 USB 线。** 2026-09-16 两次尝试都是 `devicectl` 报
`State: unavailable` / `transportType: None`（paired 但没连上）——
**判有线只看 `devicectl list devices --json-output` 的 `connectionProperties.transportType`**，
文本输出不含这一列，而 `ioreg -p IOUSB | grep -i iPhone` 会命中 IOKitDiagnostics 的
诊断转储给出假阳性（本轮踩过一次）。

iPhone 16 Pro UDID `00008140-000161D62112801C`（`scripts/device-test.sh` 默认设备）。
iPad Air 5 `00008103-001C71490E62201E` **还没点过「信任证书」**。

```bash
scripts/device-test.sh \
  -only-testing:blindRunTests/BlindOrderFlowPresentationTests \
  -only-testing:blindRunTests/KeepWaitingTests \
  -only-testing:blindRunTests/EmergencySOSTests \
  -only-testing:blindRunTests/AppRealtimeCoordinatorTests \
  -only-testing:blindRunUITests/AccessibilityAuditTests
```

**这一轮新增 / 改向的用例（全部零执行，跑之前不要当成绿的）**：

| 用例 | 它守什么 |
|---|---|
| `EmergencySOSTests.testSafetyHubDowngradesToLocalCallOutsideOfTheActiveRun` | 七个骨架态逐个判 `.localCall`，反向钉 `IN_PROGRESS` 仍是 `.cloudTrigger` |
| `EmergencySOSTests.testLiveShareTileIsAppendedLastAndNeverDisplacesTheDialingTiles` | 分享格排最后、拨号三项下标不动、标题随分享中翻面 |
| `AppRealtimeCoordinatorTests.testCancellationWarningDropsTheDeletedButtonHintWhilePendingMatch` | 两条通道一起换 |
| `...testCancellationWarningIsLeftIntactWhileRematchingBecauseTheButtonExists` | 反向：按钮还在就一个字不改 |
| `...testCancellationWarningFallsBackToTheSafeCopyWhenNoOrderIsKnown` | 看不到订单时按「没按钮」处理 |
| `...testCatchUpAppliesTheSameCancellationWarningOverride` | 断线补读走同一条覆盖 |
| `KeepWaitingTests.testOnlyRematchingActuallyRendersTheKeepWaitingControl` | 两条判定刻意不同步 |
| `KeepWaitingTests.testRepeatStatusStaysSilentAboutKeepWaitingWhilePendingMatch` | 播报不许指向已删按钮 |
| `AccessibilityAuditTests.testBlindOrderStatusMatchingStateOffersCancelAndRuleNoticeInsteadOfKeepWaiting` | **整条改向**（原名 `...OffersKeepWaitingWhileWaitingForAMatch`） |
| `AccessibilityAuditTests.testSafetyHubOutsideTheActiveRunOffersLocalDialInsteadOfCloudSOS` | 本地拨号 + 无云端键 + 分享格在。**本轮唯一能钉住「订单页真的把 `resolve` 传进求助中心」的用例** —— 单测那条只测纯函数 |
| `EmergencySOSTests.testSafetyHubCopyDoesNotClaimARunIsUnderwayBeforeItStarts` | 两档文案分开（含反向断言） |
| `AppRealtimeCoordinatorTests.testCancellationWarningTakesTheSaferSideWhenTwoOrdersAreRegistered` | 两张单在册时取保守侧 |
| `...testCancellationWarningIgnoresOrdersThisEventCannotBeAbout` | 反向：无关状态不算候选，防判据恒覆盖 |
| `...testCancellationWarningReplacementIsTrueInBothWaitingStates` | 替代正文在两态下都得是真话 |

**改向 / 修探针的既有用例 4 条**：上表最后两行之外，
`KeepWaitingTests` 的 `testLimitReachedRemovesTheActionForThisOrder`、
`testRepeatStatusMentionsKeepWaitingWhileWaiting`、
`testRepeatStatusDropsKeepWaitingOnceTheLimitIsReached` 三条把订单状态从
`.pendingMatch` 换成 `.rematching`（前者那个按钮已删，用它会红在自己的前提上）；
`AccessibilityAuditTests.testBlindOrderStatusInLandscapePassesAccessibilityAudit`
的「页面起来了」探针从 `blindOrderStatusKeepWaitingButton` 换成 `blindOrderFlowStatusCard`
（前者永远等不到，而失败信息会写着「订单状态页没起来」指向一个不存在的故障）；
`AppRealtimeCoordinatorTests.testSuppressionFollowsEventTypeNotBodyText` 的取样
eventType 从 `ORDER_CANCELLATION_WARNING` 换成 `REMATCH_TIMEOUT`（前者现在有正文覆盖）。

🔴 **按失败签名判，不按红绿判**（记忆 `regression-baseline-must-match-suite-set`）。
从 result bundle 取明细，别只看汇总行：

```bash
xcrun xcresulttool get test-results tests --path <bundle> --format json
xcrun xcresulttool export attachments --path <bundle> --output-path /tmp/att
```

**已知既有 3 条红**（iPhone 16 Pro，与本 PR 无关，`BlindBookingView` 本轮一字未动）：
`testBlindBookingPassesAccessibilityAudit`（Text clipped ×1）、
`testBlindBookingInLandscapePassesAccessibilityAudit`（Contrast ×1）、
`testBlindFirstRunHelpPassesAccessibilityAudit`（Text clipped ×2）。

---

## 阶段 3b 做完了什么（`7c726dc`）

1. **求助中心底部在非 `IN_PROGRESS` 降级为本地拨号** —— 这是 3a 引入的**静默失败**，
   不是新功能。骨架底部那枚「求助与安全」让求助中心第一次能在四个非 `IN_PROGRESS`
   态打开，而云端求助只在 `IN_PROGRESS` 开放 ⇒ 按下红胶囊：`beginCountdown` 落
   `.failed`、倒计时不弹、而骨架那屏没有 `EmergencyStatusNotice` 的渲染点 ⇒
   **屏幕零变化、一个字不播**。判据复用 `BlindHomeSOSMode.resolve`。
   拨号弹窗 `context` 随之改成按状态算（写死 `.cloudFailed` 会对没按过求助的人说
   「求助没有发出去」）。`AGENTS.md` §6 已改口径。
2. **`ORDER_CANCELLATION_WARNING` 正文按状态覆盖**（`AppRealtimeCoordinator.overriddenBody`）。
   ⚠️ **不是无条件覆盖**：同一 eventType 后端三个推送点跨 `PENDING_MATCH` 与 `REMATCHING`
   两态，后者按钮还在且是真延长 —— 无条件换会把一条可执行的提示换成「去取消重下」，
   而重新下单要求 ≥30 分钟提前量。横幅 + TTS + 断线补读三处一起覆盖。
3. **设计稿 §3.5 两处迁移**：分享实时位置 → 求助中心**最后一格**（拨号三项下标不动）；
   匹配规则说明 → 「取消匹配」二次确认弹窗（`offersDispatchAlgorithmNotice` 恰好
   与说「取消匹配」的那两态重合）。
4. **骨架新增 footer** —— `viewModel.errorMessage` 与分享结果提示原先只在
   `trackingContent` 渲染，骨架换掉那条列表后失败只剩一句 TTS。
5. **后端 handoff 已投**（见下）。

### review 修掉的 4 条 A 档（`676ebdb`）—— 全是同一个形状

新鲜上下文只看 diff 跑的 review。四条都真，且**与本轮要修的东西同源**：
「新开了一条到达路径，而那一层里的内容没跟着重判一次」。

1. 求助中心副标题/收起按钮在非 `IN_PROGRESS` 是假话 —— 上一轮只**加**了新提示、
   没**换**旧的两句。header 是 `.combine` 的 ⇒ 读屏听到一句自相矛盾的话。
2. 分享那一格在 `IN_PROGRESS` 也开着，而那一屏没有 `flowFooter` ⇒ 失败只剩 TTS。
   **本轮在修的形状，在另一个分支上新开了一个。** 判据改成
   `usesFlowSkeleton && offersRunPlanShare`：入口只出现在结果看得见的地方。
3. 正文覆盖判据 `contains` → 「候选单全都有按钮」。两张单同时在册可达
   （详情页 `onDisappear` 只 `stopPolling()`、**不 unregister**），
   否则 PENDING_MATCH 的预警会被 REMATCHING 那张「担保」着照播原文。
4. 替代正文在 `REMATCHING` 下是假话（「还没有人接单」= 其实接过又取消了）。

**B 档未动**（下次同类问题可搜）：弹层开着时 `mode` / `emergencyCallContext` 中途翻面、
`emergencyButtonReservedHeight` 仍按 84pt 胶囊算（localCall 档约 52pt 死区）、
`errorMessage` 活不过一轮轮询（5s）、`offersKeepWaiting` 现在只剩用例在读、
`AGENTS.md` 新立的「新增求助入口必须读 `resolve`」还没有机器守卫。

---

## 本轮**否掉**的一件（不要按原任务书再做）

state.md 上一版的 3b 第 1 项写着「求助中心加「重复当前状态」格子」。
**那个前提是假的，来源是一条过期注释。**

`BlindRunnerHomeView.swift` 原 824-834 行的 🗑 注释写着 `repeatStatusButton` 已删除、
「移进求助与安全中心弹层 …… 阶段 3 接入弹层入口时落地」—— 而 `5f4557d`（决策 2）
当轮就把它改成了问候行右侧一枚可见图标，那条注释没跟。核实结果：
**三个会打开求助中心的页面各已有一枚可见的「重复当前状态」按钮**
（首页 `greetingRow:712`、订单页 toolbar `blindOrderFlowRepeatStatusButton`、
执行屏 `blindActiveRunRepeatStatusButton`）。

加第七格的代价是实打实的：格子在 `ScrollView` 里，多一格把拨 120 往下推一行，
而 `AGENTS.md` 明写了拨号三项不折进二级入口的理由就是「念得出来而按不到等于没有」。
设计稿 §3.5 自己也没把这个动作放进求助中心（它写的是「轻点状态卡片重新播报」）。

那条注释已就地改成订正，并写明教训：**写「等 X 来接」的注释时，X 落地那一轮必须
回来改它** —— 否则它会被下一轮当成待办清单读。

---

## 后端 handoff（**已投**，2026-09-16）

后端仓库 `Jayden23018/blind-run-backend` 分支 `docs/blind-order-flow-field-requests`，
commit `38e66d6`（+85 行）。**投递走独立 worktree `/tmp/demo-handoff-ios-0916`** ——
主工作区 `/Users/mac/Downloads/demo` 的 `docs/handoff.md` 当时是**未解决的合并冲突态
（`UU`）**，在那份文件上落笔会把冲突标记和别人的在途合并一起带进提交。

⚠️ **还没 push。** 后端 pre-push 有一道**无条件**编译门禁（`compileJava + compileTestJava`），
本机首次拉依赖会反复断 —— 这就是全局 `CLAUDE.md` 那条「JVM 不读 `HTTP_PROXY`」：
报错写着 TLS 版本不匹配，真因是没走代理。必须带

```bash
GRADLE_OPTS="-Dhttp.proxyHost=127.0.0.1 -Dhttp.proxyPort=7897 -Dhttps.proxyHost=127.0.0.1 -Dhttps.proxyPort=7897"
```

并**循环重试**（每次多缓存一批；本轮缓存从 ~36M 涨到 197M 仍未跑完）。
跑通后 `git push -u origin docs/blind-order-flow-field-requests` 并开 PR。

投出去的内容（4 个字段 + 1 条模板建议）：

| 字段 | 设计稿用处 | 客户端当前降级 |
|---|---|---|
| 引导绳经验年数 | 「陪跑 32 次，引导绳经验 2 年」 | 只显示「陪跑 N 次」 |
| 陪跑员「已认证」 | 「张伟，已认证」 | **整段不显示**，且**先请后端判语义** |
| 附近在线人数 | 匹配态副标题「附近 6 位在线」 | 只留「已等待 mm:ss」 |
| 预计到达时间 | 出发态标题「8 分钟后到」 | 改用直线距离 |

🔴 **「已认证」那条不是简单加字段**：后端自己 2026-08-13 划过红线「客户端不得把
服务时长/星级说成『证明』『证书』『已认证』」（民政部令第 67 号），已落成守卫
`volunteer-hours-credential`，而那条词表**刻意不含「实名认证」「身份认证」**
（那些是注册流程的真实动作）。所以问的是「设计稿这个标记指的是哪一种」，
而不是「给个字段」。

⚠️ **写 handoff 时自己错过一次，留在这里防复发**：原稿断言「`data.sql` 的距离播报模板
已经在承诺 ETA，而它既没人填也没人删」。核实后两处都不成立 ——
`{{ETA}}` 在 `POST /api/orders/voice/classify-query` 的 `template` 字段里
（`api_spec.yaml:4908`），不在 `data.sql`；而那份契约的第 ② 条本来就写着占位符填不出值时
客户端**整句丢弃**，所以那里没有洞。已改成如实说明「iOS 至今一个字没消费那个字段」。
**引用「后端某处已经承诺了 X」之前，自己 grep 一次那个字符串真正在哪个文件。**

---

## 本轮之前已经做完、**不要重做**的

- 设计稿色板的 WCAG 复算（40 组 + 6 条验红，全部钉在 `FlowDesignSystemTests`）。
- 尺寸两处刻意偏离设计稿：按钮 58 → 64pt、信息列表**可点**行 52 → 64pt。
  由 `testEveryTappableMetricClearsTheSixtyFourPointFloor` 钉住。
- 设计稿四处做不到/不成立已按契约改，各配验红。
- `volunteerTotalCompleted` 漏解码已补（含 `replacingStatus` 带字段的回归用例）。
- 标签栏未选中标签 `#6B7385`（4.76:1）+ `configureWithOpaqueBackground()`。
- 6 份文档已随口径同步：`AGENTS.md` §6、`docs/05-page-specs.md`、
  `09-accessibility-and-voice-guidelines.md`、`03-user-stories.md`、
  `technical-design-overview.md`、`user-manual.md`。

---

## 已分出去的任务（别重复做）

- **PR #142（OPEN）**：掩码姓名不再被读屏念成「张星号」。
- **未开始的 chip**：判引导页 `textClipped` 是真缺陷还是误报。已查清 `fixedSize` 修不了
  （真因是 `.accessibilityElement(children: .combine)` 合成元素的几何），三跑实测表写在
  `BlindRunnerHelpView.swift` 的代码注释里。

---

## 环境事实（别重新踩）

- **真机是唯一 XCTest 通道**，模拟器因高德无 arm64-sim slice 永久不可用；CI 只跑编译门禁 + 规格校验。
- **无线跑不了 XCTest**（code 70）。判有线看 `devicectl list devices --json-output` 的
  `connectionProperties.transportType`；`ioreg -p IOUSB | grep -i iPhone` 会**假阳性**
  （命中 IOKitDiagnostics 转储）。
- `passed=0 failed=0` **一律当失败查**（零执行）。脚本对此有硬失败，别绕。
- 跑测前设备要解锁 + 自动锁定设「永不」。
- `gh` 必须显式带 `--repo Jayden23018/blind-run-ios`，裸跑会打到 upstream（JerryZhao-1）。
- 提交要**显式列路径**：`shared-checkout-guard` 会拦 `git add -A`。
- **后端仓库是共享 checkout 且常年挂着十几个 worktree**，主工作区随时可能停在别人的
  分支、甚至半个合并中间。要在后端落笔先 `git status --porcelain` 看一眼，
  需要干净基点就 `git worktree add ... origin/main` 新开一个，别切主工作区的分支。
