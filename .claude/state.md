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
- [x] **阶段 3b** — `7c726dc`，**真机零执行**（见下）
- [ ] 阶段 4 过渡动画
- [ ] 阶段 5 VoiceOver / 动态字体 / 减弱动态效果 / 触感

---

## ⏭ 下一件：把 3a + 3b 的真机验证一次跑掉（累计两轮零执行）

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
| `AccessibilityAuditTests.testSafetyHubOutsideTheActiveRunOffersLocalDialInsteadOfCloudSOS` | 本地拨号 + 无云端键 + 分享格在 |

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
