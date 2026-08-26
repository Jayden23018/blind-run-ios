# 近期变更总结 + 下单流程完整 review（2026-08-26）

**范围**：`1c9bc20`（2026-08-22）到 `5bb8cd4`（2026-08-24）这一段的新增能力、其中的决策与理由；
以及盲人端**下单全链路**（表单 / 语音 / 零输入三条路径）的逐层核查，重点是
**静默失败**、**漏掉的情况**、**用硬编码敷衍的占位实现**。

**每条结论都带 `文件:行号`。** 没有代码证据的判断一条都没写。

---

## §0 验证状态（先说清楚，别拿它当"已验证"用）

| 检查 | 结果 |
|---|---|
| `validate-guard.mjs` | ✅ 90 条守卫用例全过（守卫规则 19 条） |
| `validate-docs.mjs` | ✅ 通过 |
| `validate-spec-coverage.mjs` | ✅ 前端调用的每条路径都在契约里 |
| `validate-golden-corpus.mjs` | ✅ 103 条与前端镜像一致 |
| `validate-error-codes.mjs` | ✅ 前端映射 44 个码后端都存在（后端另有 6 个码前端未映射，见 §3.7） |
| `validate-voice-intent-words.mjs` | ✅ 本地直通表无一词被后端判成别的意图 |
| **真机 XCTest** | ❌ **没跑。** `xcrun devicectl list devices` 两台设备（iPhone 16 Pro / iPad Air 5）**都是 `unavailable`**——USB 没接。本仓库真机是唯一 XCTest 通道，所以本报告里**没有任何一条结论来自运行时观测**，全部来自读代码 + 契约对撞。 |

⚠️ **当前分支 `feat/intro-call-dispatch-flag`（PR #77）里有 4 条从未执行过的用例**，
PR 正文自己写着这一点。这正是记忆 `merged-prs-whose-tests-never-ran` 记的那个坑——
CI 的两个绿勾（"规格与文档"、"编译门禁"）**都不是测试信号**。合并前必须补
`passed=N failed=0`。

---

## §1 最近增加了什么、怎么加的、为什么这么定

三条主线，外加一批支撑性改动。

### 1.1 接单前通话磨合 `PENDING_INTRO_CALL`（PR #67，`1c9bc20`，+3739 行）

**做了什么**：订单状态机加第 10 个状态。陌生志愿者看到派单后不能直接接单，先发
`INTERESTED` → 订单进 `PENDING_INTRO_CALL` → 双方通一次电话 → 各自表态 → 都说"合适"才进
`PENDING_ACCEPT`。

**怎么加的**：`blindRun/Core/Models/IntroCallModels.swift`（新，184 行）承载契约模型与文案；
盲人侧 UI 在 [BlindOrderStatusView.swift:1410](../../blindRun/BlindRunner/BlindOrderStatusView.swift#L1410) 的
`introCallSection`；志愿者侧独立成页 `VolunteerIntroCallView.swift`（新，386 行）。

**关键决策与理由**（都写在代码注释里，不是事后总结）：

| 决策 | 理由 | 证据 |
|---|---|---|
| `RunOrderStatus` 的每个穷举 switch 都补一个显式分支，不加 `default` | 后端加状态时编译器逼一次决策，不让新状态默认掉进某个分支 | `OrderDisplayHelpers.swift` 全文无 `default:` 分支用于 `RunOrderStatus` |
| 通话期**不**对志愿者展示盲人自由文本 | 通话在接单前、派单是串行的，展示等于交给这一单碰到的每个候选人 | `OrderDisplayHelpers.swift:64` |
| 盲人侧只给"合适 / 换一位"两个按钮，**不给"没打通"** | 对盲人两者结果一样（换一位），分两个按钮只是多一次读屏滑动；后端要的 timeout/declined 口径由志愿者侧提供 | [BlindOrderStatusView.swift:1405-1408](../../blindRun/BlindRunner/BlindOrderStatusView.swift#L1405) |
| 阶段 B 仍保留"再打一次" | 阶段切换判据（点过拨号 + `scenePhase` 回 `.active`）是**推断不是事实**，用户在系统拨号确认框点"取消"会走同一条路径 | [BlindOrderStatusView.swift:1400-1403](../../blindRun/BlindRunner/BlindOrderStatusView.swift#L1400) |
| 拨号号码**只能**取 `dialableCounterpartPhone` | 掩码串拼进 `tel:` 会被 `EmergencyDialer.telURL` 取成 `1381234` 拨出去——空号，界面看不出异常 | [BlindOrderStatusView.swift:243-244](../../blindRun/BlindRunner/BlindOrderStatusView.swift#L243) |
| 先通知对方、**不等响应**就返回拨号 URL | 对盲人"点了没反应"最糟；APNs 到达与响铃之间本就有几秒差 | [BlindOrderStatusView.swift:237-241](../../blindRun/BlindRunner/BlindOrderStatusView.swift#L237) |

### 1.2 派单推送带 `requiresIntroCall`（`786362c`，PR #77，当前分支唯一实质提交）

**做了什么**：后端 `aea3fc9` 把 `requiresIntroCall` 补进 `NEW_ORDER` 载荷，客户端据此决定
`/respond` 发 `ACCEPT` 还是 `INTERESTED`。此前一律发 `INTERESTED`，代价是**已磨合过的一对**
和**距开跑已不够聊一轮**的单子都要多打一通本不必打的电话。

**三处刻意选择**：

1. 字段解成 `Bool?` 而非 `Bool`，缺失落回 `INTERESTED`
   （[WebSocketModels.swift:222-241](../../blindRun/Core/Models/WebSocketModels.swift#L222)）。
   理由：契约标必填，但非可选意味着缺键时**整条 `WSNewOrder` 解不出来** →
   志愿者连派单弹窗都看不到、静默退出派单池。⚠️ 但配套的"缺失不是静默的"这句话
   **在 Release 构建下不成立**，见 §3.3。
2. `ACCEPT` 被回 409 `INTRO_CALL_REQUIRED` 时**自动改发 `INTERESTED` 重试一次**
   （[VolunteerHomeView.swift:194-208](../../blindRun/Volunteer/VolunteerHomeView.swift#L194)）。
   理由：推送是后端判断的一个快照，发出后 `IntroCallPair` 或开关都可能变，而志愿者只有 30 秒倒计时。
3. **不解释** `requiresIntroCall=false` 的原因。三种成因（功能关闭 / 已磨合过 / 时间不够）
   客户端分不出来，写任何一种都可能是错的。

**连带修的**：`INTRO_CALL_REQUIRED` 的文案原本让志愿者"请先选『有意向，想先聊聊』"，
而这条路径下界面上只有"接单"一个按钮——指的是一个不存在的按钮
（[ErrorModels.swift:69-75](../../blindRun/Core/Models/ErrorModels.swift#L69)）。

### 1.3 SPEC-E 激励体系（PR #76，`089960e`，+2974 行）

四块：**志愿者积分**、**双人火花（连续周数）**、**固定搭档（收藏 + opt-out）**、**邀请码**。

**关键决策**：

| 决策 | 理由 | 证据 |
|---|---|---|
| 积分与"志愿服务时长"**分两屏**、文案不得互相换算 | 中央网信办 2026-06-19 专项整治通知第 2 条点名整治"宣传可获得志愿服务时长"。信息架构层隔开比靠文案自律可靠 | [VolunteerPoints.swift:10-16](../../blindRun/Volunteer/VolunteerPoints.swift#L10) |
| `delta == 0` 的流水**绝不过滤** | 它表示"这一单撞了防刷上限、没有加分"，`note` 里有人话原因。过滤掉 = 跑完了、订单完成了、积分没动、界面什么都没有 | [VolunteerPoints.swift:42-46](../../blindRun/Volunteer/VolunteerPoints.swift#L42) |
| `reason` 收成 `String` 不是 Swift `enum` | 封闭枚举会让后端下次加取值时**整条响应解不出来** = 盲人端一整页空白（AGENTS.md 硬约束，commit `4793805`） | [VolunteerPoints.swift:48-54](../../blindRun/Volunteer/VolunteerPoints.swift#L48) |
| 邀请码入口挂在**选身份**而不是登录页 | 登录页是登录/注册合一入口，老用户每次都经过 → 等于开一个"随时补填邀请码"的刷分入口。设角色天然只能成功一次 | [InviteCode.swift:103-105](../../blindRun/Shared/InviteCode.swift#L103) |
| 邀请码逐字播报走 `Text.speechSpellsOutCharacters()`，**不自己插顿号** | 插顿号 VoiceOver 会念出标点或吞掉，且拿不到读屏自己的拼读语速 | [InviteCode.swift:36-39](../../blindRun/Shared/InviteCode.swift#L36) |
| 收藏文案只能说"更可能"，不得说"优先派给" | 契约逐字：收藏只影响派单**排序**、不影响资格，加分不压倒一切 | [PartnerStreaks.swift:295](../../blindRun/Shared/PartnerStreaks.swift#L295) ⚠️ 这条自己破了一处，见 §3.6 |
| 收藏"不够格"与"这个 id 不是志愿者"同码同文案，客户端**不区分** | 区分开就等于确认这个 id 是个志愿者，端点变成枚举接口 | [ErrorModels.swift:77-81](../../blindRun/Core/Models/ErrorModels.swift#L77) |

### 1.4 支撑性改动（同期）

- `ef0ab3a` / `9d535da`：装饰地图在**真 key 构建**下仍被读屏遍历——隐藏挪进合成元素那一层；
  7 条长红真机 UI 测试修回绿（1 条真误触缺陷会真的拨 110 + 6 处用例陈旧），并落守卫
  `stale-ui-test-identifier`。
- `ae37540`：契约漂移改成 pre-push 自动检查——直接告诉你哪几个字段没接。
- `f404de2`：登出清干净 + 常用地点不再明文落盘 + 号码掩码（审计 F4/F5/F10）。
- `8a0ab5f`：主 App 隐私清单归位，阿里云 SDK 的清单不再冒充我们的（ITMS-91053）。

---

## §2 现在的下单流程（端到端）

### 2.1 三条入口，一个提交出口

```
                    ┌─ 语音向导 VoiceOrderWizard ─┐
盲人首页 ──下单──→   ├─ 分步表单 4 步 ────────────┤ → BlindBookingViewModel.submit()
                    └─ 零输入两步确认 ───────────┘        └→ POST /api/orders
```

三条路径**共用同一个 view model 和同一个提交函数**
（[BlindBookingView.swift:835](../../blindRun/BlindRunner/BlindBookingView.swift#L835)），
这是这套设计里最对的一个决定：门槛判定、请求构造、错误播报只有一份。

### 2.2 五道下单门槛（顺序即优先级）

[BlindBookingView.swift:130-143](../../blindRun/BlindRunner/BlindBookingView.swift#L130)：

```
basicProfile → identityVerification → emergencyContacts → startPoint → appointmentTime
```

- 前三道要去别的页面补，所以**进页面就播报**
  （`announceEntryGateIfNeeded`，[:794](../../blindRun/BlindRunner/BlindBookingView.swift#L794)）——
  否则用户填完四步撞上一个灰按钮，看不见屏幕的人只会当成"点了没反应"。
- 语音向导启动前跑同一套门槛（[VoiceOrderWizard.swift:208-212](../../blindRun/Voice/VoiceOrderWizard.swift#L208)），
  避免"说完一整句才被服务端 403 拒掉"。
- 审阅步的按钮禁用状态与提示文案**用同一个源** `firstMissingGate`
  （[:309-318](../../blindRun/BlindRunner/BlindBookingView.swift#L309)）——曾经这里手抄了后三道，
  少的正是要去别的页面补的前三道。
- **定位权限被拒不是门槛**，是可听可见的降级告知
  （`locationDegradationNotice`，[:289-296](../../blindRun/BlindRunner/BlindBookingView.swift#L289)）。
- **演示坐标不许当下单起点**（[:540-543](../../blindRun/BlindRunner/BlindBookingView.swift#L540)）：
  只对 Mock 与 UI 测试放行。否则 `resolvedStartPlace` 永不为 nil，`.startPoint` 那道门槛在生产里是死代码。

### 2.3 语音路径的轮次

1. **整句轮**：一次 `POST /api/orders/voice/parse` 抽三个槽位。
   这一轮**吞掉所有错误但不静默**——端点不存在（`NOT_FOUND`）直接交回表单，
   其余失败带 `parseFailureNotice` 继续走读回
   （[VoiceOrderWizard.swift:448-501](../../blindRun/Voice/VoiceOrderWizard.swift#L448)）。
2. **消歧轮**（可选）：起点撞同名地点时**先让用户挑再读回**——顺序不是偏好，
   读回念的是"最佳猜测"，用户听完多半就说确认（[:491-499](../../blindRun/Voice/VoiceOrderWizard.swift#L491)）。
   三次挑不出来时**说出"按第一个来"**，静默取第一条正是这轮要消灭的失败（[:542-543](../../blindRun/Voice/VoiceOrderWizard.swift#L542)）。
3. **确认轮**：两档判定——本地整串命中（确认/再念一遍/重说）零延迟直通，
   其余交后端（方言、长句、"我想改时间"）。本地表是后端正则的**子集**，由
   `validate-voice-intent-words.mjs` 逐词对撞钉住。

### 2.4 请求构造

[BlindBookingView.swift:800-833](../../blindRun/BlindRunner/BlindBookingView.swift#L800)。三处值得记：

- `startAddress` 用**完整地址**，读回念 `addressShort`（POI 名）——契约里两者分工明确：
  念的是名字（听得出对不对），下单带的是门牌号（走得到）。
- 终点三项一律从 `BookingEndPlace` 取，坐标成对由 `init` 保证
  （[OrderModels.swift:453-463](../../blindRun/Core/Models/OrderModels.swift#L453)）。
- `hasGuideDogThisRun` 是**三态不是布尔**：`nil`=没提（后端回落档案），`false`=本次明确不带。
  这个字段进派单**硬过滤**，塌缩任一方向都会静默改掉候选池。

### 2.5 提交与后续

`submit()` → `POST /api/orders` → 201 → 播"订单提交成功，系统正在为你派单。" →
`onOrderCreated(response)` → 首页导航到 `.orderStatus(id)`
（[BlindRunnerHomeView.swift:702-707](../../blindRun/BlindRunner/BlindRunnerHomeView.swift#L702)）。

订单状态页 5 秒轮询兜底 WebSocket。

---

## §3 发现的问题

按严重度排序。每条都给了**复现路径**和**证据行号**。

> §3.5 是**在写这份报告的过程中被 pre-push 契约漂移闸抓出来的**，不是读代码读出来的。
> 记在这里是因为它说明那道闸在做实事：它抓到的是"后端已经把你挂在 handoff 里的问题
> 修好了、而你不知道"这一类——读客户端代码永远读不出来。

### 3.1 🔴 P0 — 通话数据拉不到时，盲人端整块操作区消失，而播报还在叫他打电话

**现象**：订单进 `PENDING_INTRO_CALL` 后，`GET /api/orders/{id}/intro-call` 只要失败一次
（网络抖动、5xx、解码失败），盲人的订单状态页就变成：状态卡还在、播报说
**"有位志愿者想陪你跑，可以打个电话聊聊。"**，而**拨号按钮、"合适"按钮、"换一位"按钮
一个都不渲染，也没有任何错误文字或播报**。

**证据链**：

1. 拉数据用 `try?`，失败即 `introCall = nil`，无任何记录：
   [BlindOrderStatusView.swift:217-226](../../blindRun/BlindRunner/BlindOrderStatusView.swift#L217)
   ```swift
   let view: IntroCallView? = try? await appState.apiClient.get(
       IntroCallEndpoint.view.path(orderId: order.orderId)
   )
   introCall = view
   ```
2. 整个操作区被 `let introCall` 拆包卡住，nil 时 `@ViewBuilder` 返回空：
   [BlindOrderStatusView.swift:1411](../../blindRun/BlindRunner/BlindOrderStatusView.swift#L1411)
   ```swift
   if order.status == .pendingIntroCall, let introCall = viewModel.introCall {
   ```
3. 播报仍然是"可以打个电话聊聊"：
   [OrderDisplayHelpers.swift:296-297](../../blindRun/Core/Models/OrderDisplayHelpers.swift#L296)
4. **文案本身是有的**——`IntroCallCopy.loadFailed`，但它只在**按下拨号按钮**时才播
   （[BlindOrderStatusView.swift:1474-1476](../../blindRun/BlindRunner/BlindOrderStatusView.swift#L1474)），
   而这一状态下那个按钮根本没渲染出来。

**讽刺的地方**：`refreshIntroCallIfNeeded` 的文档注释写着
"拿不到就把 `introCall` 清空：那一刻界面上唯一该有的动作是拨号，而没有号码的拨号按钮
按下去就是「点了没反应」"——它躲开了一个静默失败，造出了另一个更彻底的：
**连按钮都没有，用户连"点了没反应"的机会都没有**。

**后果**：盲人被告知"可以打个电话"，然后在页面上找不到任何可按的东西。20 分钟通话窗口
在这期间照常倒计时，超时后订单换下一个候选人。轮询每 5 秒重试可能自愈，但用户在自愈前
完全无从判断发生了什么。

**建议（最小改动）**：`refreshIntroCallIfNeeded` 改成区分"没拉到"与"不该有"，
`introCallSection` 在 `status == .pendingIntroCall && introCall == nil` 时渲染
`IntroCallCopy.loadFailed` + 一个"重新加载"按钮。**不要**改成静默重试——
重试和告知不是二选一。

**测试缺口**：`blindRunTests/IntroCallTests.swift` 26 条用例，**没有一条**覆盖
"view 拉取失败时盲人看到什么"。

---

### 3.2 🟠 P1 — 没说时长的单子静默写死"一小时"，而复核页明说"未填写"

**现象**：用户没指定时长时，请求里 `plannedEndTime = 开始时间 + 3600 秒`，
**这个数字从头到尾没有任何一处告诉过用户**。

**证据链**：

1. 硬编码在这里，唯一一处，无具名常量：
   [BlindBookingView.swift:807-810](../../blindRun/BlindRunner/BlindBookingView.swift#L807)
   ```swift
   } else {
       let endDate = appointmentTime.addingTimeInterval(3600)
       plannedEndTime = DateFormatter.aidRunBackendLocalDateTime.string(from: endDate)
   }
   ```
2. 复核页此时显示的是 **"未填写选填跑步需求。"**：
   [BlindBookingView.swift:1898-1899](../../blindRun/BlindRunner/BlindBookingView.swift#L1898)，
   因为"预计时长"那一行只在 `resolvedDurationMinutes != nil` 时才加
   （[:415-417](../../blindRun/BlindRunner/BlindBookingView.swift#L415)）。
3. 这个数字**不是无害的**。后端 `OrderTimeoutScheduler`：
   `plannedEnd + 15min` 推 `ORDER_OVERDUE`、`+60min` **自动完成订单**
   （[openspec/.../surface-planned-end-and-overdue-alert/design.md:10](../../openspec/changes/surface-planned-end-and-overdue-alert/design.md#L10)）。
   分享链接有效期也是 `max(plannedEndTime, now) + 2h`（`api_spec.yaml:2375`），
   家属靠 `plannedEndTime` 判断"是不是该到了"（`api_spec.yaml:6048`）。
4. 服务开始后，这个用户从没同意过的时刻会被**念给他听**：
   [OrderDisplayHelpers.swift:487-489](../../blindRun/Core/Models/OrderDisplayHelpers.swift#L487)
   ```swift
   case .inProgress:
       guard let plannedEndForAnnouncement else { return status.blindRunnerAnnouncement }
       return "\(status.blindRunnerAnnouncement)预计\(plannedEndForAnnouncement)结束。"
   ```
5. **这条分支没有任何测试。** 唯一断言 `plannedEndTime` 的用例
   [blindRunTests.swift:3146](../../blindRunTests/blindRunTests.swift#L3146) 里
   `viewModel.duration = .sixty`，走的是 `if` 那一支；全仓搜 `3600` 只有生产代码这一处
   命中 `makeCreateOrderRequest`。

**最坏的路径是零输入下单**：那条路径专门服务"语音坏了、屏幕看不见"的用户，
没有复核屏，按钮标题就是整单——而 `zeroInputSummary`
（[:458-462](../../blindRun/BlindRunner/BlindBookingView.swift#L458)）只念
"从X出发，Y 开始，直接下单"，**一个字不提结束时间**。这个用户跑到 1 小时 15 分时
会收到"跑者可能失联"级别的告警，2 小时整订单被自动完成。

**建议**：两个方向，选一个即可，别都做。
- （推荐，最小）把默认时长提成具名常量 `AppConstants.Timing.defaultBookingDurationMinutes = 60`，
  并在 `optionalReviewItems` / `zeroInputSummary` 里**无条件念出结束时刻**
  （"未指定时长时按 1 小时计"）。念一句的成本远低于一次假告警。
- 或者干脆不猜：`plannedEndTime` 缺省时问用户。但这会给零输入路径加一步，与那条路径的
  存在理由冲突——不建议。

---

### 3.3 🟠 P1 — "缺 `requiresIntroCall` 不是静默降级"这句话只在 DEBUG 构建下成立

**现象**：`WSNewOrder.requiresIntroCall` 缺失时落回 `INTERESTED`，代码注释与提交信息都
声称这个降级"会被记进志愿者首页那条『派单诊断』，**是屏幕上看得见的面包屑**"。
**在 Release / Demo / Production 构建里，那条诊断整块被编译掉了。**

**证据链**：

1. 声称：[WebSocketModels.swift:230-232](../../blindRun/Core/Models/WebSocketModels.swift#L230)
   > 缺失不是静默的：`WebSocketService` 会把 `failedField: "requiresIntroCall"` 记进派单诊断，
   > 那条诊断渲染在志愿者首页（`VolunteerHomeView` 的「派单诊断：…」）。
2. 同样的话在 [WebSocketService.swift:427-430](../../blindRun/Core/WebSocketService.swift#L427)
   与 `786362c` 的提交信息里各写了一遍。
3. 实际渲染点**在 `#if DEBUG` 里**：
   [VolunteerHomeView.swift:1349-1357](../../blindRun/Volunteer/VolunteerHomeView.swift#L1349)
   ```swift
   #if DEBUG
   if let diagnostic = appState.realtimeCoordinator.dispatchDiagnostic {
       Text("派单诊断：\(diagnostic.debugSummary)")
   ```
4. 全仓搜 `dispatchDiagnostic` / `debugSummary`：**只有这一个渲染点**，也没有落日志。

**后果**：字段缺失本身的降级是对的（不让志愿者静默退出派单池），但"我们有观测"这个前提
在生产里不成立。真出现契约漂移时，现象是"熟人也被要求打电话"——一个功能性退化，
而**线上没有任何信号**。更糟的是下一个人读到那段注释会以为这条路已经有观测了。

**顺带**：`WSDispatchDiagnostic.advancing(to:)`
（[WebSocketService.swift:61-72](../../blindRun/Core/WebSocketService.swift#L61)）会把
`failedField` 一路带到 `.retained` / `.presented`，于是**一次成功的派单**在诊断里
也挂着 `failedField=requiresIntroCall`。记忆 `silent-decode-degradation-bug-class` 记的
"别拿 failedField 当失败判据"在这里换了个方向重现：现在它连"成功"也标了。

**建议**：要么把注释改成实话（"只在 DEBUG 可见"），要么给这条降级一个**生产可见**的出口
（`ClientFlowDiagnostics.record` 已有基础设施，[WebSocketService.swift:444](../../blindRun/Core/WebSocketService.swift#L444) 那行旁边就是）。
**不要**只改注释就算完——按 AGENTS.md §1，这属于"能被静态检查抓到"的一类。

---

### 3.4 🟠 P1 — 401 在下单/接单路径上完全静默，盲人端尤其

**现象**：token 过期时，盲人按下"提交预约"→ 整个 App 跳回登录页，
**一句话都没播**。原因只以红色小字写在登录页上。

**证据链**：

1. 下单：[BlindBookingView.swift:856-863](../../blindRun/BlindRunner/BlindBookingView.swift#L856)
   ```swift
   } catch let error as APIError {
       isSubmitting = false
       if appState.handleAuthenticatedAPIError(error) {
           return nil          // ← 不设 errorMessage、不 speakError
       }
   ```
2. 志愿者响应派单同一模式：[VolunteerHomeView.swift:224-226](../../blindRun/Volunteer/VolunteerHomeView.swift#L224)
3. `handleAuthenticatedAPIError` → `expireSession()` → `clearSession()` + 写
   `sessionExpirationMessage`（[AppState.swift:656-672](../../blindRun/Core/AppState.swift#L656)）
4. 那条消息只被赋给 `errorMessage`，**没有走语音**：
   [LoginViewModel.swift:137-140](../../blindRun/Auth/LoginViewModel.swift#L137)
   ```swift
   if errorMessage == nil,
      let sessionExpirationMessage = appState.consumeSessionExpirationMessage() {
       errorMessage = sessionExpirationMessage      // ← 同一个函数里 speechService 就在手上
   }
   ```
5. **同一个文件里其余每条错误都播**：`speakError` 出现在
   [LoginViewModel.swift](../../blindRun/Auth/LoginViewModel.swift) 的 :198 / :251 / :282 / :306 / :320。
   只有会话过期这一条没有——这不是设计取舍，是漏了。
6. 登录页那段文字是纯 `Text`，没有 header trait、没有 announcement，
   而且它在 `onAppear` 的 `configure` 里就写好了，VoiceOver 连"内容变化"都不会播：
   [LoginView.swift:298-305](../../blindRun/Auth/LoginView.swift#L298)

**语音下单路径更彻底**：`submitConfirmedBooking` 只在 `submit()` 返回非 nil 时才做事
（[VoiceOrderWizard.swift:1042-1044](../../blindRun/Voice/VoiceOrderWizard.swift#L1042)），
401 时它返回 nil，向导也不说话——用户说完"确认"，然后是完全的沉默。

**建议**：`LoginViewModel.configure` 里那一行后面补 `speechService?.speakError(...)`。
一行，改在源头，两个调用点都修好。

---

### 3.5 🟠 P1 — 后端已经把"志愿者杀进程就回不到通话页"修好了，前端没接（本轮 push 时被契约漂移闸抓出来）

**这条不是读代码读出来的，是 pre-push 的契约漂移闸拦下来的**，值得单独记一笔：
PR #77 自己的正文把这个洞挂在"不在本 PR 范围（都在等后端）"里，**后端已经答复并上线了**。

**证据链**：

1. 后端 `origin/main` 的 `VolunteerDispatchSummaryResponse` 新增 `introCallOrderId`
   （`api_spec.yaml:6570-6581`，逐字）：
   > 此刻正在通话磨合的那一单（`PENDING_INTRO_CALL`），没有则 null（绝大多数时候）。
   > 存在的唯一理由是**冷启动恢复**：这一态 `order.volunteer` 还是 null，
   > `GET /api/orders/{id}` 恒 403、`/api/orders/mine` 也不返回 ——
   > 志愿者杀掉 App 再打开就回不到通话页，只能等 20 分钟窗口超时，而盲人在等他。
2. 前端手写模型**没有这个字段**：
   [VolunteerDispatchSummaryModels.swift:58-79](../../blindRun/Core/Models/VolunteerDispatchSummaryModels.swift#L58)
   —— 20 个字段里没有 `introCallOrderId`。
3. 而这个端点前端**一直在调**：[VolunteerHomeView.swift:298](../../blindRun/Volunteer/VolunteerHomeView.swift#L298)
   与 [:583](../../blindRun/Volunteer/VolunteerHomeView.swift#L583)。
   ⇒ 字段在网络上到了，被 `Decodable` 静默丢弃。
4. `node scripts/validate-spec-coverage.mjs` 是**路径级**的，路径没变所以恒绿；
   抓到它的是 pre-push 的"重新生成 API 客户端并比对"那道闸：
   `❌ introCallOrderId —— 手写模型没有，运行时读不到`。

**后果**：志愿者在通话磨合期切后台被系统回收、或手动杀进程，重开 App 后
**没有任何入口回到通话页**——`GET /api/orders/{id}` 403、`/api/orders/mine` 不返回它。
只能干等 20 分钟窗口超时，而盲人这一整段时间都在等他。这正是后端加这个字段要解决的事。

**建议**：把 `introCallOrderId` 加进手写模型，志愿者首页拿到非 null 时跳
`GET /api/orders/{id}/intro-call` 恢复通话页。
🚨 契约点名：**它不在 `activeOrders` 里，也不要合并进去** —— 人还没接单，
且那一态 `sharesLiveLocation()` 为 false，混进活跃订单会让位置协同空转。
另外六个"契约新增"字段（`plannedEndTime` / `plannedStartTime` / `startAddress` /
`startLatitude` / `startLongitude` / `volunteerId`）手写模型都已有，不需要动。

---

### 3.6 🟡 P2 — 邀请码填错时静默丢弃，而它一辈子只能填一次

**证据链**：

- [RoleSelectionView.swift:47-51](../../blindRun/Role/RoleSelectionView.swift#L47)：
  `inviteCode: InviteCodeEntryCopy.sanitize(inviteCode)`
- [InviteCode.swift:135-141](../../blindRun/Shared/InviteCode.swift#L135)：
  超长（>16）或含非 ASCII 字母数字字符 → 返回 `nil`，当作没填
- 返回 nil 之后**没有任何提示**：`performRoleSwitch` 照常成功，用户听到的是设角色成功
- 而这是一次性的：`InviteCodeEntryCopy.oneShotNotice`
  ——"设定身份后无法补填"（[InviteCode.swift:121](../../blindRun/Shared/InviteCode.swift#L121)）

**触发场景一点都不刁钻**：中文输入法残留一个全角字符、粘贴时带了个空格在中间、
读屏用户口述输入多了一位。代价是双方各 20 积分，**永久损失且不可申诉**。

**注意**：不拦住注册是对的（注释里的理由成立：为一个可有可无的邀请码打断盲人注册流程是灾难）。
**缺的只是告知**。警告 ≠ 阻断。

**建议**：`sanitize` 返回 `Result` 或让调用方在 `nil` 且原文非空时播一句
"你填的邀请码格式不对，已按未填写处理"。仍然不阻断。

---

### 3.7 🟡 P2 — "不得承诺优先派单"这条红线自己破了一处，而且被测试钉住了

**证据链**：

- 红线：[PartnerStreaks.swift:295](../../blindRun/Shared/PartnerStreaks.swift#L295)
  `favoriteExplanation = "设为固定搭档后，系统派单时会更可能派给他，但不保证一定是他。"` ✅
- 破的那处：[PartnerStreaks.swift:341](../../blindRun/Shared/PartnerStreaks.swift#L341)
  `optOutConfirmMessage = "退出后你将不再被优先派给这位跑者，且需要重新一起跑一单才能恢复。"` ❌
- 守这条红线的用例**只覆盖 3 个字符串**，`optOutConfirmMessage` 不在列表里：
  [IncentiveAdoptionTests.swift:332-341](../../blindRunTests/IncentiveAdoptionTests.swift#L332)
- 而另一条用例**反过来断言它必须含"不再被优先派给"**：
  [IncentiveAdoptionTests.swift:316](../../blindRunTests/IncentiveAdoptionTests.swift#L316)

**后果**：同一个机制，对盲人说"更可能"、对志愿者说"优先派给"。志愿者被告知他当前**享有**
一个系统并不保证的待遇。不是安全问题，但是同一个 PR 里自相矛盾的两条断言——
而且因为被测试钉住了，**它永远不会自己漂回正确的说法**。

**建议**：把 `optOutConfirmMessage` 改成"退出后系统派单时不再更可能派给这位跑者"，
并把它加进 `testFavoriteCopyNeverPromisesPriorityDispatch` 的列表，同时修
`testOptOutConfirmationSpellsOutTheConsequence` 的断言词。

---

### 3.8 🟢 P3 — 其余，逐条

| # | 问题 | 证据 | 判断 |
|---|---|---|---|
| a | 下单成功但 `response.id == nil` 时**不导航、不报错**，而"提交成功"已经播出去了 | [BlindRunnerHomeView.swift:704-706](../../blindRun/BlindRunner/BlindRunnerHomeView.swift#L704) + [BlindBookingView.swift:854](../../blindRun/BlindRunner/BlindBookingView.swift#L854) | 契约里 `id` 是 required（`api_spec.yaml:4096`），所以是防御分支。但一旦触发，用户停在下单页、再按一次会撞 `DUPLICATE_ORDER`。`else` 里补一句播报即可 |
| b | `OrderResponse.success` 是**后端从不返回**的字段（契约 `OrderResponse` 只有 id/status/message），只有 `MockAPIClient` 造它 | [OrderModels.swift:489-494](../../blindRun/Core/Models/OrderModels.swift#L489) vs `api_spec.yaml:4071-4098`；Mock 造值在 [MockAPIClient.swift:1569](../../blindRun/Core/MockAPIClient.swift#L1569) | 生产代码零读取，**目前无害**。但这正是记忆 `mock-fabricates-fields-the-backend-never-sends`（PR #48）那个缺陷的形状，删掉比留着安全 |
| c | `searchPlaces(triggeredBySpeech:)` 的参数**声明了、传了、从不读** | [BlindBookingView.swift:616](../../blindRun/BlindRunner/BlindBookingView.swift#L616) 与 [:651](../../blindRun/BlindRunner/BlindBookingView.swift#L651) | 死参数。删掉 |
| d | `bookingCoordinate` 里 `normalize(...)?.coordinate ?? currentLocation` 是失败**开放** | [BlindBookingView.swift:550-552](../../blindRun/BlindRunner/BlindBookingView.swift#L550) | 查过了：`normalize` 只在坐标非法时返 nil（[CoordinateSystem.swift:38](../../blindRun/Map/CoordinateSystem.swift#L38)），此时落回的也是同一个非法坐标，**不会产生坐标系错乱**。对比 [VolunteerLocationReporter.swift:31](../../blindRun/Volunteer/VolunteerLocationReporter.swift#L31) 是 `guard let` 失败关闭——两处口径不一致，但当前无实际后果 |
| e | 后端 6 个错误码前端未映射：`FAVORITE_ADDRESS_LIMIT_EXCEEDED` / `ORDER_SELF_DISPATCH_FORBIDDEN` / `POINT_TRANSACTION_ALREADY_REVERSED` / `SHARE_LINK_GONE` / `SUPPORT_TICKET_ALREADY_CLOSED` / `SUPPORT_TICKET_LIMIT_EXCEEDED` | `node scripts/validate-error-codes.mjs` 输出 | 门禁**单向**（只查"前端有的后端也有"），所以恒绿。降级路径是显示后端的中文 `message`（[APIClient.swift:91-95](../../blindRun/Core/APIClient.swift#L91)，`message` 契约上 required），**不是**"未知错误"。但后端 message 不是按 TTS 写的。`FAVORITE_ADDRESS_LIMIT_EXCEEDED` / `SHARE_LINK_GONE` 对应的功能前端都有，优先补这两个 |

---

## §4 查过了、不是问题（防止下一轮重提）

1. **`try?` 满仓 113 处**——逐条看过：绝大多数是 `Task.sleep`（无意义可失败）、
   `MockAPIClient` 内部的请求体探测、`APIClient` 的错误体多形状兜底。
   `BlindOrderStatusView.swift:1871-1944` 那批 `try?` 状态跃迁**全在 `#if DEBUG` 的
   Mock 测试面板里**（[:1859-1861](../../blindRun/BlindRunner/BlindOrderStatusView.swift#L1859)），
   不影响生产。真正有问题的只有 §3.1 那一处。
2. **`TODO` / `FIXME` / 占位实现**——全仓 41 处包含"写死/占位"字样的行，
   **一处都不是待办**，全是解释"为什么这里不写死"的注释。这个仓库在这一项上是干净的。
   唯一的真硬编码是 §3.2 的 `3600`。
3. **`ErrorCode.prefersServerMessage`**——**已不存在**。它是 `DUPLICATE_ORDER` 一码两义时期的
   止血补丁，后端拆出 `REVIEW_ALREADY_SUBMITTED`（`7bce0b3`）后前端已撤掉
   （`docs/backend-open-questions-2026-07-31.md:71`）。之前的项目记忆里还留着它，已作废。
4. **`ErrorCode.localizedMessage` 的穷举 switch 无 `default`**
   （[ErrorModels.swift:84-181](../../blindRun/Core/Models/ErrorModels.swift#L84)）——
   后端加码时编译器会逼一次决策，这是对的，不要为了"防御"加 `default`。
5. **`isRespondingToDispatch` 成功路径不复位**——看着像泄漏，实际由
   `dismissDispatch()`（[VolunteerHomeView.swift:274-279](../../blindRun/Volunteer/VolunteerHomeView.swift#L274)）
   在成功分支里复位。不是缺陷。

---

## §5 修复优先级建议

按"改动量 ÷ 后果"排：

1. **§3.4（401 静默）** — 一行，改在 `LoginViewModel.configure`，两条路径一起修好。
2. **§3.1（通话数据拉不到）** — 一个 `else` 分支 + 一条用例。这是唯一的 P0。
3. **§3.5（`introCallOrderId` 没接）** — 后端已经上线了，前端加一个字段 + 一条恢复路径。
   它和 §3.1 是同一个功能的两个洞（一个是"拉失败没兜底"，一个是"冷启动回不去"），
   建议同一个 PR 一起修。
4. **§3.2（写死一小时）** — 具名常量 + 复核/零输入播报里念出结束时刻 + 一条用例钉住 nil 分支。
5. **§3.3（诊断只在 DEBUG）** — 先把注释改成实话（5 分钟），生产观测另开一件事。
6. **§3.7（文案红线）** — 改一个字符串 + 调两条断言。
7. **§3.6（邀请码静默丢弃）** — 一句播报。
8. §3.8 a/b/c — 顺手清理，别单开 PR。

⚠️ **在这些之前**：PR #77 那 4 条从未执行过的用例得先在真机上跑一遍
（设备现在 `unavailable`，接 USB 后 `scripts/device-test.sh -only-testing:blindRunTests/IntroCallTests`）。
带着没跑过的用例合进 main 是本仓库已经犯过两次的错。

---

## 复核触发条件

- §3.1 / §3.2 / §3.4 任一被修
- 后端把 `requiresIntroCall` 改成非必填，或 `PENDING_INTRO_CALL` 的窗口/状态语义变化
- `plannedEndTime` 的后端超时口径（`+15min` / `+60min`）变化
- 下单三条路径（表单 / 语音 / 零输入）任一有信息架构改动
- CI 获得真机 XCTest 通道（届时 §0 的验证状态整段作废）
