# 视障用户「语音预约陪跑服务」的界面与交互标准调研

> **交付说明**：本文件是计划模式下的临时载体。批准后原样落盘到
> `docs/research/blind-voice-booking-ia-20260805.md`（`tech-decision-research` skill 规定的位置）。
> **调研档位**：C 档（完整选型），7 条并行线：国外竞品 / 国内竞品 / 强制标准 / 语音学术与工程 /
> 反对意见 / 二态与 gate 时机 / 仓库现状盘点。
>
> **来源分级**：`[A]` 一手规范原文·官方文档·平台 API ｜ `[B]` 竞品可核查实证 ｜
> `[C]` 学术研究·行业报告·无障碍机构测评 ｜ `[D]` 二手博客·社区讨论。
> **`[D]` 不单独支撑任何硬性建议。** 找不到证据的地方一律写「未找到证据」。

---

## 0. 执行摘要

**结论一：产品方的「减法」方向对，但论证支柱是错的。**「占屏幕大半的主按钮」对 A 类（全盲 + VoiceOver）
**几乎零收益** —— VoiceOver 选中后在屏幕任意位置双击即可激活，物理面积不参与激活 `[A]`；WCAG 2.5.5 的
受益者写的是运动障碍与低视力，不是屏幕阅读器用户 `[A]`。大按钮该做，但它服务的是 B 类，不是减少 A 类的成本。

**结论二：Magic Tap 不能承担「熟练用户不退化」的论证。** 它不是你的按键：用户可全局重映射、iOS 26 起可整个关闭、
第三方采用率极低、无实现时会冒泡到系统播放/暂停音乐 `[A][D]`。Apple HIG 本身要求核心功能有一条以上路径 `[A]`。
正确的加速键是 **App Shortcuts（iOS 16+，可编程，锁屏可用）** —— Be My Eyes 与小艾帮帮都走这条 `[A][B]`。

**结论三：确认词白名单必须重做，这是本报告最硬的一条。** 2018 年 Portland 事件是 Amazon 官方复盘的完整证据链：
背景对话中的 **"right"** 满足了确认，直接完成了不可撤销动作 `[B]`。项目当前白名单里的
**「好」「行」「对」「是」** 是同构的单音节高危词，且陪跑场景下志愿者就在身边说话。建议只保留 ≥3 音节的
显式短语。方向性错误代价不对称这一点，`design.md` 决策 2 已经论证对了，但白名单本身没执行到位。

**结论四：12 秒尾静音要改。** 它超过 Nielsen 的 10 秒注意力上限 `[C]`，是 Dialogflow no-speech 默认值的 2.4 倍 `[A]`。
自发语音停顿的第三模态在 1500ms `[C]`。建议 **2000ms 尾静音 + 显式「说完了」 + 整块内容区可点结束**（后两者提案已有）。

**结论五：反对「有订单时整页接管、下单入口消失」，改为「订单卡是第 1 个 VoiceOver 焦点」。**
对 VoiceOver 用户，「第一个焦点」在功能上已经等于接管，不必真的删掉别的内容。删掉会制造 NN/g 意义上的强模式 `[C]`，
且 DoorDash 的并发下单数据说明「进行中还想再下单」是真实行为 `[B]`。真正的答案是 Apple 给的：Live Activity `[A]`。

**结论六：三处标准编号要纠正。** ① **`YD/T 4211-2023` 不是无障碍标准**，它是《域名服务隐私泄露风险防护指标要求》`[A]`，
不存在该编号的适老化标准，任务书里这个编号是错的；② WCAG **2.5.5 是 AAA 不是 A**，AA 的那条是 2.5.8（24×24 CSS px）`[A]`；
③ Apple HIG 现行表述是 **default 44×44 pt / minimum 28×28 pt**，「Apple 最小 44」是过时说法 `[A]`。

**取舍**：首页焦点从 10 降到 5（无订单）/ 6（有订单）是可达的，但**省下的 4-5 次滑动不是瓶颈**。
盲人语音输入 80.3% 的时间花在编辑纠错上 `[C]`，纯音频复核会漏掉约 50% 的 ASR 错误 `[C]`。
**把预算压在首页焦点数上，可能优化了一个不是瓶颈的环节。** 真正的杠杆在确认与纠错的正确性。

---

## 1. 目标用户与成功判据的外部校准

### 1.1 「≤3 决策点」对标竞品是什么水平

| 产品 | 核心任务决策点 | 说明 | 来源 |
|---|---|---|---|
| Be My Eyes | **1** | 点 `Call a Volunteer`，或直接 `"Hey Siri, make a call with Be My Eyes"` | `[A]` [官方帮助](https://support.bemyeyes.com/hc/en-us/articles/360005522738-Call-a-sighted-volunteer) |
| Aira | **1** | 点 `Call Aira`，接通后**口头说需求** —— 需求不是表单填的 | `[A]` [官方](https://aira.io/aira-explorer-app/) |
| 小艾帮帮 | **1** | 长按大按钮（长按而非点击，防误触） | `[B]` [App Store](https://apps.apple.com/cn/app/id1361445580) |
| 滴滴关怀版 | **2** | 打开小程序 → 点 10 个预存常用地址之一 | `[D]` [澎湃](https://m.thepaper.cn/baijiahao_10898413) |
| 高德/嘀嗒/申程「一键叫车」 | **1** | 起点自动识别，**不输目的地**，上车后口头告知司机 | `[A]` [上海交通委](https://jtw.sh.gov.cn/zsk/20230323/2ed128b74fbb4241b9436a754cba56b6.html) |
| United In Stride | **4+** | 注册 → 搜索（半径/邮编/活动/配速/距离）→ 看 profile → 私信，之后**线下自行约** | `[A]` [官网](https://www.unitedinstride.com/) |
| **AidRun 目标** | **3** | 按「开始约跑」→ 说一整句 → 说确认 | — |

**校准结论：3 个决策点是合理的，但不是激进的。** 上述所有「即时求助/呼叫」类产品都是 **1**。
AidRun 之所以做不到 1，是因为它有一个它们都没有的约束：**预约起始时间必须 ≥ now + 30 分钟**
（`AGENTS.md` 第 5 节，后端 `APPOINTMENT_TOO_SOON`）。**没有「现在就跑」，所以不存在「一键就出发」。**
第 2 个决策点（说时间地点）是这个业务约束的直接产物，删不掉。

**一个更有价值的对标**：滴滴关怀版把「输入目的地」整个消掉的办法是**预存 10 个常用地址** `[D]`。
AidRun 的等价物是**常用出发点**。如果盲人跑者 80% 的时间从同一个地方出发（大概率成立，跑步有固定路线），
那第 2 个决策点可以退化为「说一个时间」，甚至「确认默认」。**这条比压缩首页焦点数杠杆大得多，且未在任何现有提案里。**

### 1.2 「≤60 秒」是否合理

分解目标路径的时间预算（各节点依据见第 6 节）：

| 节点 | 预算 | 依据 |
|---|---|---|
| 首页 VoiceOver 滑到主操作 | 2-4 s | 目标 IA 里主操作是第 2 个焦点 |
| 唤起 → 起音 earcon → 开麦 | ≤1 s | Nielsen 1.0 s 思维流不中断 `[C]` |
| 用户说一整句 | 5-8 s | — |
| 尾静音判定 | **2 s**（现状 12 s） | 见 §6.2 |
| `/api/orders/voice/parse` 往返 | ≤8 s（`parseTimeout`，`VoiceOrderWizard.swift:83`） | 现状实测值 |
| 读回整单 | 8-10 s | 三段式：原话 + 整单 + 两条出路 |
| 用户说确认 | 2 s | — |
| `POST /api/orders` + 成单播报 | 3-5 s | — |
| **合计** | **31-40 s** | |

**60 秒达得到，但现状达不到** —— 光「尾静音 12 s + parse 8 s」两项就吃掉 20 s，再加读回 10 s 已经 38 s，
**任何一次重问都会直接爆掉 60 秒**。所以 §6.2 把尾静音从 12 s 降到 2 s 不只是体验问题，是判据能否成立的问题。

### 1.3 建议的首页 VoiceOver 焦点上限 N

**先说证据状况：没有任何标准规定过首页焦点数上限。WCAG、GB/T 37668、工信部适老化规范、Apple HIG
都不含这类条款 —— 这是明确的「未找到证据」。** 因此 N 只能从竞品实测反推，且下面这个锚点本身是推算的。

唯一可用的锚点是 **Be My Eyes**：底部 5 个 tab（`Get support` / `Be My AI` / `Service directory` /
`Communities` / `Settings`，双源互证 `[A][B]`）+ `Get support` 页的 2 个按钮（占屏幕上半部大部分面积的
`Call a volunteer` + `Groups`）→ **推算约 7 个焦点**。
`[B]` [blindios.uk 逐 tab 走查](https://www.blindios.uk/be-my-eyes) · `[A]` [官方 Getting Started](https://support.bemyeyes.com/hc/en-us/articles/360005528557-Getting-Started-with-Be-My-Eyes)

**这个 7 是文字描述推算，不是真机 VoiceOver 实测。** 页面标题、导航栏是否可聚焦未找到证据。
AFB AccessWorld 对它的评价是「不能更简单」`[B]` [afb.org/aw/16/2/15488](https://afb.org/aw/16/2/15488)。

**AidRun 无 tab bar**，所以对标应扣掉那 5 个 tab —— Be My Eyes 的功能页本体只有 **2 个焦点**。

**建议值**：

| 形态 | N | 推导 |
|---|---|---|
| **无订单态** | **≤ 5** | Be My Eyes 功能页 2（主操作 + 次操作）+ AidRun 特有的必需项 3（状态播报 header、「重复当前状态」、设置） |
| **有订单态** | **≤ 6** | 上面 5 项，主操作位替换为订单卡 + 查看详情 + 条件性的取消 |

**现状实测（读码盘点，`BlindRunnerHomeView.swift`）**：无订单态 **10** 个，有订单态 **10-11** 个。
即需砍掉 4-5 个，具体裁决见 §4.2。

---

## 2. 强制标准清单

### 2.0 三处必须先纠正的编号错误

| 错误说法 | 事实 | 来源 |
|---|---|---|
| 「YD/T 4211-2023《移动互联网应用（APP）适老化通用设计规范》」 | **该编号不是无障碍标准。** 全国标准信息公共服务平台记载 YD/T 4211-2023 的真实名称是**《域名服务隐私泄露风险防护指标要求》**（推荐性，2023-05-22 发布 / 2023-08-01 实施，CCSA 归口）。**不存在以该编号命名的适老化标准。** 任务书与项目文档若引用过此编号，必须删除 | `[A]` [std.samr](https://std.samr.gov.cn/hb/search/stdHBDetailed?id=FE86C10A0CF73123E05397BE0A0A2FC5) |
| 「WCAG 2.5.5 触达尺寸是 A 级」 | **2.5.5 Target Size (Enhanced) 是 AAA**。AA 级的那条是 **2.5.8 Target Size (Minimum)，24×24 CSS px** | `[A]` [W3C](https://www.w3.org/TR/WCAG22/#target-size-minimum) |
| 「Apple HIG 要求最小 44×44 pt」 | 现行 HIG（2025-03 改版）写的是 iOS **Default control size 44×44 pt，Minimum control size 28×28 pt**。44 是默认值不是底线 | `[A]` [HIG Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) |

另有两处应从项目文档中撤下：

- **信息无障碍研究会（SIA）《移动应用（App）无障碍通用设计规范》—— 未找到该名称的独立文件，无法证实其存在。**
  SIA 确为 GB/T 37668-2019 起草单位之一。建议改引 GB/T 37668-2019。
- 网上流传的「ISO 9241-411 规定触控目标最小 9.0 mm / 圆形 11.0 mm」**是错的**。ISO/TS 9241-411:2012 的正式范围是
  "Evaluation methods for the design of physical input devices"，是测试方法技术规范，不是尺寸规格文件
  `[A]` [ISO 官方范围](https://www.iso.org/standard/54106.html)。可核实的 9 mm 出处是 Google 的 48×48 dp
  `[A]` [Google](https://support.google.com/accessibility/android/answer/7101858)。

### 2.1 WCAG 2.2

| 条款号 | 级别 | 原文要点 | 对 AidRun 的具体含义 | 现状是否违反 | 来源 |
|---|---|---|---|---|---|
| **2.5.8** Target Size (Minimum) | AA | 指针目标 ≥24×24 CSS px（≈3.7-4.0 mm）；有 Spacing / Inline / Essential 等 5 个例外 | 视为不可用的地板（见 §2.5） | 否，项目 64pt 远高于 | `[A]` [SC](https://www.w3.org/TR/WCAG22/#target-size-minimum) |
| **2.5.5** Target Size (Enhanced) | AAA | ≥44×44 CSS px；Understanding 明确 low vision 为受益群体并附实证引用 | B 类用户的依据 | 否 | `[A]` [Understanding](https://www.w3.org/WAI/WCAG22/Understanding/target-size-enhanced.html) |
| **2.4.3** Focus Order | A | 顺序影响含义时，可聚焦组件须以保持含义与可操作性的顺序获得焦点 | **本项目最高杠杆条款**。首页遍历顺序必须「状态 → 主操作 → 重复状态 → 辅助信息」，由 `.accessibilitySortPriority` 钉死 | 需实测。项目规则已要求「操作优先于地图」（`docs/09:77`），但**没有一条自动断言覆盖遍历顺序** | `[A]` [SC](https://www.w3.org/TR/WCAG22/#focus-order) |
| **3.3.7** Redundant Entry | A | 同一流程中先前已输入的信息应自动填充或可供选择 | 定点修改（「改时间」）后回读回，其余槽位不得要求重说 | 否（`handleConfirmCommand` 只重采单槽） | `[A]` [SC](https://www.w3.org/TR/WCAG22/#redundant-entry) |
| **3.2.6** Consistent Help | A | 帮助机制在同组页面内的相对位置保持一致 | **「重复当前状态」在每一屏的 VoiceOver 序位必须固定**。它现在在首页是第 6 个焦点，在预约页位置不同 → 新 IA 必须钉死一个恒定序位 | **可能违反，需逐页核对** | `[A]` [SC](https://www.w3.org/TR/WCAG22/#consistent-help) |
| **2.2.1** Timing Adjustable | A | 内容设定的时限须可关闭/调整/延长 | **5 秒轮询不得让 VoiceOver 焦点跳走**；语音轮的 8/12 秒静音超时属交互限时 | 需实测轮询期间的焦点行为 | `[A]` [SC](https://www.w3.org/TR/WCAG22/#timing-adjustable) |
| **2.3.1** Three Flashes | A | 一秒内闪烁 ≤3 次 | 录音指示动画 | 否，提案 §2 已明确要求且 spec 已写入（`spec.md:102`） | `[A]` [SC](https://www.w3.org/TR/WCAG22/#three-flashes-or-below-threshold) |
| **1.4.3** Contrast (Minimum) | AA | 文本 ≥4.5:1（大字号 3:1） | 与工信部适老化规范 1.3 数值一致 | 已有自动检查（`AccessibilityAuditTests` 的 `.contrast`） | `[A]` [SC](https://www.w3.org/TR/WCAG22/#contrast-minimum) |
| **1.4.11** Non-text Contrast | AA | UI 组件与图形对象 ≥3:1 | 按钮边框、地图路线 | 部分被审计覆盖 | `[A]` [SC](https://www.w3.org/TR/WCAG22/#non-text-contrast) |
| **4.1.2** Name, Role, Value | A | name/role 可程序化确定，state/value 可程序化设置并**通知变化** | 每个自定义控件需 label + `.isButton` trait + value；状态变化须发 `AccessibilityNotification` | 已有 `.sufficientElementDescription` 审计 | `[A]` [SC](https://www.w3.org/TR/WCAG22/#name-role-value) |
| **3.3.4** Error Prevention (Legal, Financial, Data) | **AA** | 产生法律承诺或财务交易的提交，必须满足**可撤销 / 已校验 / 可复核确认**三者之一 | **下单触发真实派单，落在此条**。项目同时满足「可复核确认」（读回 + 显式肯定）与「可撤销」（`canBlindRunnerCancel`）。这是提案最强的合规依据 | 否 | `[A]` [Understanding](https://w3c.github.io/wcag21/understanding/error-prevention-legal-financial-data.html) |

> **注**：WCAG 2.2 已删除 4.1.1 Parsing（obsolete）；4.1.2 仍为现行 A 级。

### 2.2 Apple HIG 与 iOS Accessibility API

| API / 指南 | 可用版本 | 要点 | 对 AidRun 的含义 | 来源 |
|---|---|---|---|---|
| HIG Mobility | — | iOS default 44×44 pt / **minimum 28×28 pt**；「控件之间的间距和尺寸同等重要」，带 bezel 约 12 pt padding，无 bezel 约 24 pt | 求助按钮与取消按钮之间至少 24 pt 净距 | `[A]` [HIG](https://developer.apple.com/design/human-interface-guidelines/accessibility) |
| HIG Vision | — | 「理想情况下让文本可放大至少 200%」；正文默认 17 pt | 禁止 `.font(.system(size:))` 写死 | `[A]` 同上 |
| HIG Typography | — | 「字号增大时同步放大有意义的图标」「保持信息层级不随字号改变」 | 用 `isAccessibilityCategory` 在超大字号下切纵向堆叠，**主操作按钮必须仍在首屏** | `[A]` [Typography](https://developer.apple.com/design/human-interface-guidelines/typography) |
| `accessibilityElement(children:)` | iOS 13+ | `.ignore`（默认）/ `.combine` / `.contain`；**Rotor 必须配 `.contain`** | 项目已在地图（`:506`）与 `BlindStatusCard`（`:655`）用 `.combine`。位置摘要区块**未合并**，白占 2 个焦点 | `[A]` [doc](https://developer.apple.com/documentation/swiftui/view/accessibilityelement(children:)) |
| `.accessibilityAction(.magicTap)` | **iOS 13+** | `AccessibilityActionKind` 含 `.default` `.delete` `.escape` `.magicTap` `.showMenu` | **API 名核实无误**，SwiftUI 里就是这个写法 | `[A]` [AccessibilityActionKind](https://developer.apple.com/documentation/swiftui/accessibilityactionkind) |
| `accessibilityRotor(_:entries:entryLabel:)` | **iOS 16+** | 必须挂在 `ScrollView` 或其内可访问元素上 | 目标用户「不会转子」，**不建议投入** | `[A]` [doc](https://developer.apple.com/documentation/swiftui/view/accessibilityrotor(_:entries:entrylabel:)) |
| `AccessibilityNotification.Announcement / .ScreenChanged` | **iOS 17+** | 可用 `AttributedString` 设 `accessibilitySpeechAnnouncementPriority = .high` | **项目基线 iOS 16 ⇒ 必须写 availability 分支**，iOS 16 回落 `UIAccessibility.post(notification:argument:)` | `[A]` [doc](https://developer.apple.com/documentation/accessibility/accessibilitynotification/announcement) |
| `@ScaledMetric` | iOS 14+ | `init(wrappedValue:relativeTo:)` 可绑 `Font.TextStyle` | **64 pt 应写成 `@ScaledMetric(relativeTo: .body) var hitSize: CGFloat = 64`**，否则大字号下按钮不跟着长，对 B 类是倒退。现状是硬编码 `.frame(minHeight: 64)` | `[A]` [doc](https://developer.apple.com/documentation/swiftui/scaledmetric) |
| `\.accessibilityReduceMotion` | iOS 13+ | true 时避免大幅动画 | 录音指示动画必须降级为静态（spec 已要求） | `[A]` [doc](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion) |

#### Magic Tap 的官方定义与「一个 App 只能有一个」的核实结果

**Apple 从未写过「一个 App 只能有一个 Magic Tap 行为」。** 实际机制是**响应链**，效果近似但不等价：

> "It searches for the method using the responder chain, **starting with the element that has the VoiceOver
> focus**. If no object implements the appropriate method, UIKit performs the **default system action** for
> that gesture. For example, the Magic Tap gesture plays and pauses music playback from the Music app if no
> Magic Tap implementation is found from the current view to the app delegate."
> `[A]` [Apple 归档文档](https://developer.apple.com/library/archive/featuredarticles/ViewControllerPGforiPhoneOS/SupportingAccessibility.html)

`accessibilityPerformMagicTap() -> Bool`，iOS 6+，语义是 "toggling the most important state of the app"
`[A]` [doc](https://developer.apple.com/documentation/objectivec/nsobject-swift.class/accessibilityperformmagictap())。

**对 AidRun 的含义**：若只在某一页注册，其他页两指双击会**冒泡到系统默认，突然播放音乐** —— 盲人在等志愿者时被
突然放歌是真实缺陷。要么在 App 根视图注册兜底，要么全局不用。**不得把 SOS 绑到 Magic Tap**：
`AGENTS.md` 第 6 节要求求助必须逐字二次确认，而 Magic Tap 的「切换最重要状态」语义与「需确认的高风险动作」冲突。

#### 非视觉发起机制的官方能力矩阵

| 机制 | 第三方能否用来「启动录音并进入某流程」 | 关键限制 | 来源 |
|---|---|---|---|
| **App Intents / App Shortcuts** | **能** | **iOS 16+**，`AppShortcutsProvider`，用户可用预置口语短语直接唤起。Siri 触发需联网 | `[A]` [doc](https://developer.apple.com/documentation/appintents/appshortcutsprovider) |
| **Controls（控制中心 / 锁屏 / Action Button）** | **能**，可 "launch your app to a specific view" | **iOS 18+**。App Intent 需同时勾 app 与 widget extension target | `[A]` [Creating controls](https://developer.apple.com/documentation/widgetkit/creating-controls-to-perform-actions-across-the-system) |
| **Action Button（iPhone 15 Pro+）** | 能，但**只能用户自己在设置里绑定**，App 不能占用 | iOS 18 起可绑 Control | `[A]` 同上 |
| **Back Tap（轻点背面）** | 能，但**只能用户手动绑定 Shortcut**，无注册 API | iPhone 8+ / iOS 14+；厚壳可能失败 | `[A]` [Apple Support](https://support.apple.com/en-us/111772) |
| **Magic Tap** | 能，但见上文缺陷 | 可被用户全局重映射；iOS 26 起可整个关闭 | `[A][D]` |
| **摇一摇** | 未找到任何官方无障碍指引 | — | 未找到证据 |

**落地结论：iOS 16 基线下，唯一可编程的非视觉入口是 App Shortcuts。** Controls 需 iOS 18，只能作增强。
Back Tap / Action Button 只能写进用户引导文档，**不能当作产品保证的能力**。

### 2.3 中国大陆标准

| 标准 | 条款号 | 强制性 | 原文要点 | 对 AidRun 的含义 | 来源 |
|---|---|---|---|---|---|
| **无障碍环境建设法** | **第三十二条** | **法律** | 第一款：财政资金建立的网站/App「**应当**逐步符合」；第二款：交通出行等领域 App「**国家鼓励**逐步符合」 | AidRun 是商业 App ⇒ 落在**第二款「鼓励」**，非强制义务、无行政处罚。**不要在项目文档里写成强制** | `[A]` [最高检全文](https://www.spp.gov.cn/spp/fl/202306/t20230628_618991.shtml) |
| 同上 | 第三十五条 | 法律 | 「报警求助…等紧急呼叫系统，应当逐步具备语音、大字、盲文、**一键呼叫**等无障碍功能」 | **SOS 模块的立法依据**：求助入口必须可一键、可语音 | `[A]` 同上 |
| **GB/T 37668-2019** | 3.2.1.3 非文本控件 | **一级**（GB/T 为推荐性） | 「如果非文本内容是一个控件或接受用户输入，则应有一个能说明其目的的名称」 | 每个按钮必须有 `.accessibilityLabel`。**中国标准里对 SwiftUI 最直接可映射的一条** | `[A]` [正文 PDF](https://www.capa.run/static/image/img_media/_GB_T_37668-2019_信息技术_互联网内容无障碍可访问性_技术要求与测试方法_.pdf) |
| GB/T 37668-2019 | 3.2.1.4 非文本内容 | 二级 | 纯装饰内容「应以**辅助技术可忽略**的方式实现」 | **辅助地图对 VoiceOver 隐藏的条款依据**（见 §4.2） | `[A]` 同上 |
| GB/T 37668-2019 | **3.3.3.6 焦点顺序** | **一级** | 与 WCAG 2.4.3 同义 | 在中国标准里是**最低合规档**，比 WCAG 的 A 级还早生效 | `[A]` 同上 |
| GB/T 37668-2019 | 3.3.2.2 组件聚焦关联性 | 三级 | 「语义相同的部件应设置**联合的单一聚焦框**而非分别设置」 | 直接对应 `.accessibilityElement(children: .combine)`。**位置摘要区块违反此条**（现为 2 个独立焦点） | `[A]` 同上 |
| GB/T 37668-2019 | 3.2.4.2 临时/自动隐藏控件 | 三级 | 「淡出或定时消失的界面控件…应提供替代的反馈方式」 | Toast 必须同时 `.Announcement` 播报 | `[A]` 同上 |
| GB/T 37668-2019 | **3.3.4.2 语音输入** | 三级 | 「应为需要用户进行文本输入的输入栏，提供用语音进行输入的替代输入方式」 | **语音下单是标准明文要求**，可直接写进合规论证 | `[A]` 同上 |
| GB/T 37668-2019 | 3.5.1.2 功能性组件功能 | 一级 | 页面局部更新后新增组件亦须正常工作 | **WebSocket 推送后新增的 UI 必须重新纳入无障碍树** | `[A]` 同上 |
| **工信部《APP 适老化通用设计规范》**（工信厅信管函〔2021〕67号 附件2） | 1.1 字型 | 部门规范性文件 | 主要文字最大字体 ≥30 dp/pt；适老版 ≥18 dp/pt | 项目现规范「body ≥20pt」高于适老版底线 | `[A]` [湖南省政府全文](http://www.hunan.gov.cn/zqt/zcsd/202104/t20210416_16470434.html) |
| 同上 | **1.2 行间距** | 同上 | 「段落内文字的行距至少为 **1.3 倍**，且段落间距至少比行距大 1.3 倍」 | **项目现有规范未覆盖此条，需补** | `[A]` 同上 |
| 同上 | 1.3 对比度 | 同上 | ≥4.5:1（>18 dp/pt 时 3:1） | 与 WCAG 1.4.3 一致 | `[A]` 同上 |
| 同上 | **2.1 组件焦点大小** | 同上 | 「**适老版界面**中的主要组件可点击焦点区域 ≥**60×60** dp/pt；其他页面主要组件 ≥44×44」 | 60×60 只适用于适老版界面；**普通界面中国下限是 44×44**。项目 64 pt 高于全部 | `[A]` 同上 |
| 同上 | **2.4 浮窗** | 同上 | 关闭按钮「只可在左上、右上、中央底部，且最小点击响应区域不小于 44×44」 | **求助二次确认弹窗的关闭按钮位置被硬性限定，需核对** | `[A]` 同上 |
| 同上 | 3.x 手势 | 同上 | 「避免需 **3 个或以上手指**才能完成的复杂手势操作」 | 与目标用户「不会三指手势」一致 | `[A]` 同上 |
| 同上 | 4.1 辅助技术 | 同上 | 「不应禁止或限制…读屏软件的接入与使用」 | 全文中**唯一**涉及屏幕阅读器的条款，且只是消极义务 | `[A]` 同上 |

**强制性效力排序**：法律（无障碍环境建设法）> 强制性国标 GB > 推荐性国标 GB/T > 行业标准 YD/T（推荐性）>
部门规范性文件（工信部适老化规范）> 团体标准。

> **本项目适用的全部技术文本都是推荐性或规范性文件，没有一条是强制性国标。**
> 真正的硬约束来自 App Store 上架审核与工信部专项行动评测，不是法律责任。

**建议的合规基线：GB/T 37668-2019 一级 + 二级全部条款。** 工信部适老化规范是老年人导向，
对全盲用户几乎没有可测试要求，**不适合当主基线** —— 放大字体对 A 类用户完全无意义。

**修订风险**：GB/T 37668-2019 复审结论为**修订**（计划号 20252537-T-469，2025-07-01 下达，周期 12 个月）；
《移动互联网应用程序适老化技术规范》国标（计划号 20231997-T-339）**尚未发布**。半年内应复查一次。
`[A]` [std.samr](https://std.samr.gov.cn/gb/search/gbDetailed?id=91890A0DA54C80C6E05397BE0A0A065D)

### 2.4 EN 301 549

现行 V3.2.1 (2021-03) 引用 WCAG 2.1 AA；**V4.1.0 为 2025-11 公众意见稿，对齐 WCAG 2.2**。
与 WCAG 是包含关系，与中国标准是并行关系，**无冲突**。三条补充值得单独看：

| 条款号 | 要点 | 相对 WCAG 的补充 | 来源 |
|---|---|---|---|
| **11.5.2.3** 使用无障碍服务 | "shall use the applicable **documented platform accessibility services**" | **比 WCAG 更硬**：必须走平台原生 API。自绘控件绕过无障碍树即不合规 | `[A]` [加拿大等同采用版](https://accessible.canada.ca/en-301-549-accessibility-requirements-ict-products-and-services-11-software) |
| **11.5.2.15** Change notification | 变化通知 | **WCAG 里没有独立条款**，这正是 `AccessibilityNotification` 的规范依据 | `[A]` 同上 |
| **11.7** User preferences | "shall **follow the values of the user preferences** for platform settings for: units of measurement, colour, contrast, font type, font size, and focus cursor" | **本项目最容易失分的一条**：App 内自定义字号/配色若不跟随 Dynamic Type / Increase Contrast / Bold Text 即违规。WCAG 无同等强度要求 | `[A]` 同上 |

> **11.7 应直接写进 `aidrun-ship-check`。** 它是「64 pt 必须写成 `@ScaledMetric`」这条建议的规范出处。

### 2.5 触达尺寸三方差异裁决

**换算前提**：

| 候选 | 物理尺寸 |
|---|---|
| WCAG 2.5.8 = 24×24 CSS px | ≈ **3.7-4.0 mm** |
| Apple HIG default = 44×44 pt / 工信部普通界面 44×44 | ≈ **6.9-7.3 mm** |
| 工信部**适老版界面** 60×60 | ≈ 9.4-10.0 mm |
| **本项目 64 pt** | ≈ **10.0-10.6 mm** |

**实证曲线**：

- **Parhi, Karlson & Bederson (2006)**, MobileHCI '06（N=20，单手拇指）离散点击错误率：
  **3.8 mm → 29.9%**；5.8 mm → 12.9%；7.7 mm → 5.0%；9.6 mm → 2.8%；11.5 mm → 1.6%。
  原文推荐**单目标 ≥9.2 mm，多目标 ≥9.6 mm**。`[C]` [DOI](https://dl.acm.org/doi/10.1145/1152215.1152260)
- **Henze, Rukzio & Boll (2011)**, MobileHCI '11（**1.2 亿次野外触摸**）：
  "Below **15mm** the error rate dramatically increases and jumps to over **40%** for targets smaller than **8mm**."
  实验室数据系统性低估真实错误率约 3 倍。`[C]` [PDF](https://nhenze.net/uploads/100000000-Taps-Analysis-and-Improvement-of-Touch-Performance-in-the-Large.pdf)
- **Leitão & Silva (2012)**, PLoP '12（N=40，**65-95 岁**）：tap 准确率在 **<14 mm 时显著下降**（P<0.001）；
  满意档（>97%）为 **≥14 mm ≈ 87 pt**。`[C]` [PDF](https://mural.maynoothuniversity.ie/id/eprint/6045/1/PS-Target-Spacing.pdf)
- **Kobayashi et al. (2011)**, INTERACT 2011：逐字建议 "Use larger targets (**8 mm or larger** in size)"。
  `[C]` [PDF](https://opendl.ifip-tc6.org/db/conf/interact/interact2011-1/KobayashiHMAHI11.pdf)
- **Kane, Wobbrock & Ladner (2011)**, CHI '11（**10 名盲人 vs 10 名明眼人**）：盲人点击指定位置的质心偏差
  **110.97 px vs 48.84 px（Z=-15.52, p<.0001）—— 约 2.3 倍**。准则逐字："This problem can be reduced by
  **increasing target size**." 并 "Favor edges, corners, and other landmarks."
  `[C]` [PDF](http://faculty.washington.edu/wobbrock/pubs/chi-11.05.pdf)
- **Bi, Li & Zhai (2013)**, CHI '13 FFitts Law：手指存在与速度无关的**绝对精度地板** ——
  「目标太小可以靠放慢弥补」是错的。`[C]` [PDF](https://www3.cs.stonybrook.edu/~xiaojun/pdf/FFitts.pdf)

**裁决**：

| 候选 | 判定 |
|---|---|
| **24×24 CSS px** | **不可用**。落在 Parhi 的 29.9% 错误率档、Henze 的 >40% 档。W3C Understanding 文档**不引用任何研究**支持 24（对比之下 2.5.5 的 44 有完整引用清单）。工作组 issue [#1831](https://github.com/w3c/wcag/issues/1831) / [#1894](https://github.com/w3c/wcag/issues/1894) 直接索要 24 的实证依据，公开范围内**未找到含依据的回复** |
| **44 pt** | **平台/中国合规下限，非人因最优**。低于本次找到的**每一个**手持点击实证建议值（8 / 9.2 / 10.5 / 14 mm） |
| **64 pt（本项目）** | **站得住，且偏保守**。精确覆盖 Parhi 的 9.2/9.6 mm，高于 Kobayashi 的 8 mm，进入 Leitão 的「可接受」档，但低于其「满意」档 14 mm ≈ 87 pt。**维持 64 pt，不需要改** |

**四条修订建议**：

1. **把内规精确表述为「最小命中区 64 pt」而非「最小视觉尺寸 64 pt」。** SwiftUI 可用
   `contentShape` / `padding` / `frame(minHeight:)` 让命中区脱离视觉尺寸 ——「64 pt 会挤爆布局」这个反对意见在本平台大部分可绕开。
2. **64 pt 写成 `@ScaledMetric(relativeTo: .body)`**（EN 301 549 §11.7 依据）。现状是硬编码。
3. **禁止用间距替代尺寸**（即禁用 WCAG 2.5.8 的 Spacing 例外）。Colle & Hiszem (2004) 与 Leitão & Silva (2012)
   两项独立研究都发现**间距对准确率无显著影响，起作用的是尺寸** `[C]`。
4. **关键控件不要贴屏幕物理边缘。** Henze 野外数据：<12 mm 目标边缘错误率 **31.68%** vs 中心 **17.59%** `[C]`；
   且 iOS 已把边缘征用给系统手势（左=返回，下=Home，上=通知/控制中心）。
   边角对盲人的价值是**触觉地标**（Kane 2011 支持），不是 Fitts 增益。

> **但请注意这条尺寸论证的杠杆有限。** 手指探索路径下尺寸主导（Kane 2011 偏差 2.3×；
> Joh et al. 2022, W4A '22, N=12 视障，目标越大越快 `[C]` [DOI](https://doi.org/10.1145/3493612.3520454)）；
> **但 swipe-to-next 顺序导航路径下，尺寸是否主导——未找到直接实验证据**。
> 若 AidRun 的 A 类用户主要走 swipe 导航，**64 pt 是正确但低杠杆的投入**，
> 瓶颈在遍历顺序（WCAG 2.4.3 / GB/T 37668 3.3.3.6，两者都是最低档强制项）、语义分组、标签质量与状态播报。

---

## 3. 竞品分析

### 3.1 对比总表

| 产品 | 平台 | 首页元素/焦点数 | 核心任务步数 | 语音能力形态 | 证据 |
|---|---|---|---|---|---|
| **Be My Eyes** | iOS/Android/桌面/Meta 眼镜 | 底部 **5 tab**（双源互证）+ Get Support 页 2 按钮 → **推算 7**，未实测 | **1 步** | `"Hey Siri, make a call with Be My Eyes"` **免配置**；另支持自定义 Siri Shortcut | `[A]`·`[B]` [官方](https://support.bemyeyes.com/hc/en-us/articles/360005528557-Getting-Started-with-Be-My-Eyes) · [blindios.uk](https://www.blindios.uk/be-my-eyes) |
| **United In Stride** | **纯网站，无原生 App** | 未找到证据（搜索在会员墙后） | 4+ 步，且**平台不参与调度** | 无 | `[A]` [官网](https://www.unitedinstride.com/) |
| **Aira Explorer** | iOS/Android/Web | 1 个大 `Call Aira` + `Access AI`；tab 总数未找到证据 | **1 步**，接通后口头说需求 | 未找到证据 | `[A]` [官方](https://aira.io/aira-explorer-app/) |
| **小艾帮帮** | iOS/Android | 未找到证据 | **1 步（长按）** | **Siri 快捷指令**「使用小艾帮帮呼叫志愿者」，必需关键词「小艾帮帮」「呼叫」 | `[B]` [App Store](https://apps.apple.com/cn/app/id1361445580) |
| **滴滴关怀版/老年版** | 微信小程序 | 未找到证据（仅定性「明显更简洁」） | **2 步**（打开 → 点预存的 10 个常用地址之一） | 无语音下单；配人工热线 4006881700 | `[D]` [澎湃](https://m.thepaper.cn/baijiahao_10898413) |
| **滴滴盲人无障碍出行** | iOS/Android 主 App | 未找到证据 | 认证一次性前置；下单**全程靠系统读屏** | **乘客端无独立语音下单**；语音播报在**司机端**（接单/到达/即将到达三节点） | `[D]` [网易](https://m.163.com/dy/article/IAGMU1CA0519C6T9.html) |
| **高德助老打车** | 小程序 | 未找到证据；入口在首页中下方「助老」 | **1 步**，起点自动识别、**不输目的地** | 未找到语音下单证据 | `[D]` [网易科技](https://www.163.com/tech/article/GJHUJ7RB00097U7R.html) |
| **高德视障导航**（2024-08） | App | — | — | 盲道优先路线；**路口/红绿灯语音倒计时播报**；偏航实时预警 | `[B]` [新华社](http://www.news.cn/tech/20240819/005fbcd95df64564b42b0e8961ce2819/c.html) |
| **嘀嗒助老出行** | 小程序 | **5 大功能** | 一键叫车 | 无语音下单；有「**定位话术**」帮老人向司机描述位置 | `[D]` [人民网](http://bj.people.com.cn/n2/2021/0325/c82840-34639797.html) |
| **申程出行**（上海） | App + 线下扬招杆 | 未找到证据；「蓝色一键叫车按钮颇为醒目」 | 一键叫车 | 智慧屏**逐字语音引导**（见 §6.1） | `[A]` [上海交通委](https://jtw.sh.gov.cn/zsk/20230323/2ed128b74fbb4241b9436a754cba56b6.html) |
| **美团打车助老** | App | 未找到证据 | 一键叫车 | **进入即语音播报操作提示** | `[D]` [北京日报](https://news.bjd.com.cn/2023/11/27/10631357.shtml) |
| **支付宝长辈模式** | App | 「**首页仅保留财富和公益两个卡片**」 | — | 无 | `[D]` [新榜](https://www.newrank.cn/article/detail/17613) |
| **微信关怀模式** | App | 未精简功能，**只做视觉改造** | — | 无 | `[D]` [中国日报](https://cn.chinadaily.com.cn/a/202109/27/WS6151640ca3107be4979f0016.html) |
| **保益悦听**（手机读屏） | Android | 接管全系统，无首页概念 | 单指触摸播报 → **任意位置双击**激活 → 双指拖动翻屏 | 讯飞嵌入式 TTS | `[B]` [小米商店](https://m.app.mi.com/detail/36668) |
| **点明安卓**（手机读屏） | Android | 同上 | 听到「**有可操作项**」后**先左后右**手势打开快捷菜单 | 讯飞双语音库，支持粤语/英文 | `[B]` [应用宝](https://sj.qq.com/appdetail/com.dianming.phoneapp) |
| **争渡读屏** | **PC 端为主，非手机方案** | — | ZDSR 键 + 组合键 | `ZDSR+Tab` = **重复朗读焦点信息** | `[A]` [官方文档](https://www.zdsr.com/docs/zdsr/30/) |
| **Seeing AI** | iOS/Android | 2025 改版后 **3 tab**（Read/Describe/More） | 1 步 | 未找到证据 | `[B]` [Henshaws](https://www.henshaws.org.uk/hints-and-tips/seeing-ai-the-2025-update/) |
| **Microsoft Soundscape** | **已停更**（2023-01 下架，MIT 开源） | — | — | — | `[A]` [微软](https://www.microsoft.com/en-us/research/product/soundscape/support/) |
| **黑暗跑团等国内助盲跑团** | **无独立 App/小程序** | — | 微信群发报名链接 → 志愿者统计配对 → 地铁闸机口接送 | 无 | `[B]` [新华网](http://www.news.cn/20240820/70ddc2ea18a749699d48f6636eb7841e/c.html) |

> **对 AidRun 最重要的一条竞品事实**：**国内目前不存在专门的助盲跑陪跑报名 App 或小程序** `[B]`。
> 这意味着没有直接竞品，也意味着**没有现成的用户习惯可继承** —— 全部交互契约需自建并做真人验证。

### 3.2 重点拆解

#### 3.2.1 United In Stride —— 业务模型最近，但**不是派单模型**

**平台结论**：官网主导航为 Find a Partner / About / Resources / Donate / Login，**全站无任何 App 提及**，
App Store 搜索亦未命中 `[A]`。（这是「未见」不是「确证不存在」。）

**交互序列**（官方 Get Started + 搜索页字段）：

1. 免费注册，创建 profile（所在地 + 活动偏好）
2. 进入 **Find A Partner** —— 实测未登录直接返回登录页，**搜索在会员墙后**
3. 搜索字段：找 Guides / VI Athletes / Both；搜索半径；邮编；Walk / Run / Both；
   **可选配速区间**；**可选距离**
4. 结果以**地图图钉**（红钉 = 陪跑志愿者）+ **表格**双形式呈现
5. 通过 `Send Message` 私信
6. **时间地点全靠双方私信商定，平台不参与调度**

**重大变更**：已移交 **Achilles International** 运营，功能迁入 Rosterfy，
新老会员都需完成 Achilles 注册**含背景审查（background check）**
`[A]` [迁移公告](https://www.achillesinternational.org/blog/unitedinstride)。

> **可迁移的具体一条**：在下单槽位中增加「**配速区间**」与「**训练距离**」两个可选字段。
> UIS 作为该业务全球唯一成熟平台，匹配维度是「角色 + 半径 + 邮编 + 活动类型 + **配速** + **距离**」六项；
> AidRun 当前下单只有时间 + 地点 + 时长，缺了陪跑场景最实际的两个匹配维度 —— **配速不匹配的志愿者接单等于无效派单**。
> **需要人工确认**：这两个字段是否已在后端 `docs/api_spec.yaml` 的下单请求体中存在；不存在则先走后端契约变更，iOS 侧不得先行。
> （注：项目现有 `runningNeeds` 步骤已含 pace preference 与 route preference 选填字段，需先核对是否已覆盖。）

#### 3.2.2 Be My Eyes —— 「一个按钮」范式的标杆

**首页结构（双源互证，本次调研最硬的界面数据点）**：底部 **5 tab**：
`Get support` → `Be My AI` → `Service directory` → `Communities` → `Settings`
`[B]` [blindios.uk](https://www.blindios.uk/be-my-eyes)（视障者写给视障者的 iOS 指南，逐 tab 描述）
+ `[A]` [官方 Getting Started](https://support.bemyeyes.com/hc/en-us/articles/360005528557-Getting-Started-with-Be-My-Eyes)

**Get support 页元素**：
- `Call a volunteer` 巨型按钮，原文 **"occupying most of the top half of the screen"** `[B]`
- 其下 `Groups` / `My Groups`，用于呼叫自己信任的联系人 `[A]`

→ **推算首屏约 7 个焦点。这是推算不是实测**，标题与导航栏是否可聚焦未找到证据。

**历史对照（说明 7 是收敛后的结果，不是起点）**：2018 年版更极端 —— 底部只有 `Home` 与 `Stories` 两个面板，
**屏幕中央整块大空白就是呼叫区，手指触摸后抬起即发起求助** `[D]`（布局已过时）
[Neil Squire 评测](https://www.neilsquire.ca/eyes-app-review/)。

**呼叫序列**：
1. 落在 `Get support`（默认 tab）
2. 按 `Call a Volunteer` —— **或完全跳过 App**：`"Hey Siri, make a call with Be My Eyes"`，**免配置**
   `[A]` [官方 Siri 说明](https://support.bemyeyes.com/hc/en-us/articles/360007464677-iOS-Use-Siri-with-Be-My-Eyes)
3. 振铃，等 15-30 秒接通（按主语言优先匹配，无则降级次语言；>1 分钟建议挂断重拨）
4. 单向视频 + 双向语音，双方全程匿名
5. `End Call`
6. 评分：`Good` / `Problems`

**已知 VoiceOver 缺陷（可直接抄成 AidRun 的回归用例）**：AI 分析完成后**焦点跳到按钮而不是描述文本**，
用户必须靠近屏幕顶部触摸找回文本起点再双指下滑连读 `[B]`。

> **可迁移的具体一条**：为「**查询当前订单状态**」注册 App Intent / Siri Shortcut，使其可从锁屏与 AirPods 发起。
> 这是 `aidrun-a11y-voice` 里「重复当前状态」按钮的上一层 —— 盲人在路边等志愿者时解锁再找按钮，成本远高于一句 Siri。
> **红线：SOS 绝不可挂 Siri 快捷指令。** `AGENTS.md` 第 6 节要求求助必须走逐字锁定的二次确认；
> 语音快捷指令天然绕过确认，且志愿者在场时可被诱导触发。**仅「查状态/播报当前状态」可暴露给 Siri。**

#### 3.2.3 滴滴 —— 两条产品线，别混为一谈

**关怀版/老年版**（2021-01-22 全国试运行）：微信小程序，面向 60+；实名后可存 **10 个常用地址**，
「让打车变成两步走」；大字号、无广告优惠位；配电话叫车热线 `[D]`。

**盲人无障碍出行服务**（2023-07-23 全国上线，与中国盲协签约）：**不是简化界面，而是派单权 + 司机侧协议**。
核心是「优先派单」+ 司机端三节点播报 + 无障碍勋章。截至 2024 年底 305 万司机完成认证，累计超 100 万次服务 `[D]`。

**视障侧交互序列（据公开报道重建）**：
1. 「我的/个人中心」→「无障碍服务认证」，一/二级视障方可开通（**一次性前置，不在下单流程内**）
2. 下单：**全程依赖系统读屏**遍历常规界面，**无专用语音通道**
3. 等车页：安卓读屏可读到「车辆与自己的距离」
4. 行驶页：可读到距目的地公里数、时间、费用

**关键事故原话（这些是 AidRun 要防的）** `[D]`：
- 「打车的时候显示排队人数是 15 人，我等了很久才排到了车，但是司机最后取消了订单」
- 「很多司机因为不知道是盲人叫的车，如果距离太远或者找不到乘客，就取消了订单」
- 「乘客的定位有些偏移，他也不太清楚自己的具体位置，所以我绕了三圈都没找到他」
- 司机侧兜底：距终点 **200 米**时系统提示司机「帮助乘客确认下车是否安全」

**第三方测评** `[C]`（信息无障碍研究会「可及评测」，16 位视障用户线下访谈 + 211 份问卷，
满分 5 星，3 星以下 = 不能满足基本使用）：**滴滴出行 iOS 4.0 / Android 3.5**。
通病原话：「几乎每个 App 都出现了标签朗读不正确的情况，例如朗读为未加标签、朗读乱码，或不朗读」；
「缺少焦点导致无法操作，或**焦点冗余导致操作效率低**」。[capa.run 评测](https://www.capa.run/keji_content?id=31)

> **可迁移的具体一条**：把「**找不到人**」当成一等公民故障，而不是聊天兜底。
> 仿滴滴的三节点强制播报契约，在 AidRun 订单状态机上钉死：`DRIVER_EN_ROUTE`（已出发）、
> `DRIVER_ARRIVED`（已到达）、以及**新增一个接近阈值事件** —— 滴滴用 200 米，陪跑场景应更短
> （建议 **50 m**），触发「志愿者距你约 50 米」的播报 + 触觉反馈。
> 同时把嘀嗒的「**定位话术**」搬过来：`DRIVER_EN_ROUTE` 期间提供一个「播报我的位置描述」按钮，
> 用 GCJ-02 逆地理编码生成一句**可朗读、可复述给志愿者**的定位话术（不得念经纬度，`docs/09:79`）。
> **注**：项目已有 `ESCORT_DISTANCE_ALERT`，但 `AGENTS.md` 第 6 节明确它是**信息性**提示；
> 这里说的是主动的接近播报，属新能力，需先走需求与契约。

#### 3.2.4 小艾帮帮 —— 国内的 Be My Eyes，Siri 唤起契约值得抄

1. 首次启动弹 4 个权限，全部允许 → 注册（支持支付宝/微信/QQ 三方登录）
2. **长按屏幕按钮**发起求助（**长按而非点击 —— 触觉门槛替代视觉门槛，防误触**）
3. 或 Siri：「使用小艾帮帮呼叫志愿者」，**「小艾帮帮」「呼叫」为必需关键词，其余忽略**
4. 请求**同时广播给多位志愿者**，首个接受者建立单向视频
5. 视障端有**光感闪光灯**，按环境光自动开启

规模（2021-10）：盲人用户约 8700，志愿者约 6.45 万 `[D]`。
已知问题（App Store 评论）：通话时长有限制、无法回拨、通话中自动断连。
**App Store 页面明示「开发者尚未表明此 App 支持哪些辅助功能」，最后更新停在 2022-05-16 / v1.6.0** `[B]`。

> **可迁移的具体一条**：抄 **Siri 快捷指令 + 两段式必需关键词**的唤起契约 ——「应用名 + 动词」，
> 允许乱序与冗余词，只校验两个关键词。这样锁屏、口袋里、读屏未开时也能发起。
> 另：**把抢单竞争暴露给盲人端**（「已推送给 N 位志愿者」），避免滴滴那种「排队 15 人」的静默焦虑。

#### 3.2.5 读屏软件的两个可直接抄的交互

- **争渡 `ZDSR+Tab` = 重复朗读焦点信息**；`Pause` = 临时停止朗读，再按恢复 `[A]`
- **点明安卓**：听到「**有可操作项**」提示后，**先向左再向右**的手势打开快捷菜单 `[B]`
  —— 即「**先播报可用性，再提供一个廉价手势兑现它**」

> **可迁移的具体一条**：AidRun 已有的「重复当前状态」原型正是 `ZDSR+Tab`。建议做成**两级**：
> 单击 = 复述当前订单状态（含已等待时长），**双击 = 复述完整上下文**（订单号后四位、约定时间、出发点、
> 志愿者姓名与手机号后四位）。并新增「**暂停播报 / 恢复**」（对应争渡的 `Pause`）——
> **陪跑途中盲人需要临时静音以听环境音，这是跑步场景独有的、打车 App 没有的需求。**

---

## 4. 首页信息架构建议

### 4.1 推荐的目标信息架构（含 VoiceOver 焦点顺序）

**无订单态（目标 5 个焦点，现状 10）**

| # | 焦点 | 类型 | 变更 | 依据 |
|---|---|---|---|---|
| 1 | 「你还没有预约。」+ 进页面自动 `Announcement` | 合并 header（标题 + 状态摘要 `.combine`） | 现状 2 个 → 1 个 | GB/T 37668 3.3.2.2 一级「语义相同部件应设联合单一聚焦框」`[A]` |
| 2 | **「开始约跑」** | Button，≥64pt（`@ScaledMetric`），占屏幕上半部大部分面积 | 保持（已是唯一入口） | Be My Eyes `Call a volunteer` 同构 `[B]` |
| 3 | 「重复当前状态」 | Button | 保持，序位钉死 | WCAG 3.2.6 Consistent Help `[A]`；项目硬规则 + 已有测试 |
| 4 | 位置摘要（标题 + 描述合并） | 合并容器 | 现状 2 个 → 1 个 | 同 #1；且它是地图的文字等价物（`docs/09:78` 要求） |
| 5 | 设置 | Button，64×64 已有 | 保持 | — |
| — | 辅助地图 | **对 VoiceOver 隐藏**（`.accessibilityHidden(true)`），视觉保留 | 现状 2 个 → 0 个 | GB/T 37668 3.2.1.4「纯装饰内容应以辅助技术可忽略的方式实现」`[A]`；项目规则已定「地图不得承载任何必要信息」 |

**有订单态（目标 6 个焦点，现状 10-11）**

| # | 焦点 | 变更 | 依据 |
|---|---|---|---|
| 1 | **订单状态卡**（`BlindStatusCard`，已 `.combine`），进页自动 `Announcement(.high)` | 从第 4 位提到**第 1 位** | 对 VoiceOver 用户「第一个焦点」在功能上已等于接管 `[C]` |
| 2 | 「查看当前订单」 | 保持 | — |
| 3 | 「取消订单」（仅 `canBlindRunnerCancel`）| 保持条件显示 | `AGENTS.md` 第 5 节：`IN_PROGRESS` 期间不得展示取消入口 |
| 4 | 「重复当前状态」 | 序位钉死（与无订单态同为倒数第 3） | WCAG 3.2.6 |
| 5 | 位置摘要（合并） | 同上 | — |
| 6 | 设置 | 同上 | — |
| — | **下单入口** | **下沉到「设置/更多」二级，不删除、不从无障碍树移除** | 见 §4.3 |
| — | 辅助地图 | 对 VoiceOver 隐藏 | 同上 |

**条件性焦点（不计入 N，但必须有听觉终局）**：后台同步 Label（+1）、错误块（+2）。
错误块的「重试加载」当前是 `.bordered`，**无 64pt 约束**，需补。

### 4.2 现有 8 个区块逐一裁决

| # | 区块 | 现状焦点 | 裁决 | 依据 | 分级 |
|---|---|---|---|---|---|
| 1 | header（标题 / 状态摘要 / 设置） | 3 | **合并为 2**（标题+状态 `.combine`，设置独立） | GB/T 37668 3.3.2.2 一级 | `[A]` |
| 2 | 后台同步提示条 | 1（条件） | **保留**，但改为**不占独立焦点**：并入 header 的 `accessibilityValue` | 状态变化只有视觉信号会让盲人「知道变了但不知道变成什么」 | `[C]` [arXiv 1909.09078](https://arxiv.org/pdf/1909.09078) |
| 3 | 错误横幅 + 重试加载 | 2（条件） | **保留**，但「重试加载」补 64pt 约束（现为 `.bordered` 系统默认高度） | 项目 64pt 硬规则；且它是错误态下唯一出路 | `[A]` 项目规则 |
| 4 | 当前订单卡 / 新建预约区 | 2-3 | **保留**，订单卡提到第 1 焦点；新建预约区的说明 Text **删除**（内容并入按钮 `accessibilityHint`） | 说明文字对 VoiceOver 是多一次滑动，对低视力才有价值 → 视觉保留、无障碍合并 | `[A]` GB/T 3.3.2.2 |
| 5 | **「重复当前状态」** | 1 | **保留，常驻，且不得改为 Magic Tap / 摇一摇 / 长按触发** | ① 项目硬规则「可降视觉权重但不能删」；② 已有自动断言 `AccessibilityAuditTests.swift:84-98`，删掉直接挂测试；③ Magic Tap 可被用户全局重映射、iOS 26 起可关闭、无实现时冒泡到系统播放音乐；④ Apple HIG 要求核心功能有一条以上路径；⑤ 长按对目标用户（不会高级手势）是新学习成本 | `[A]`+`[D]` |
| 6 | 位置摘要 | 2 | **合并为 1**，保留 | 它是地图的文字等价物，`docs/09:78` 明确要求「map-equivalent text 必须在地图之外可用」 | `[A]` 项目规则 |
| 7 | **辅助地图** | 2 | **视觉保留，对 VoiceOver 隐藏**（`.accessibilityHidden(true)`），标题 Text 一并隐藏 | ① **视障用户是否需要地图 —— 未找到任何直接研究**；② 但项目规则已定「地图不得可交互、不得承载任何必要信息」，且它已是审计白名单唯一项；③ GB/T 37668 3.2.1.4 二级：纯装饰内容应以辅助技术可忽略方式实现；④ B 类（低视力，不开读屏）仍能看到，收益不受损 | `[A]` |
| 8 | 测试入口 | 3（DEBUG） | **无需处理** —— 已有**双重构建门禁**：`#if DEBUG` + `AppBuildChannel.current.allowsEnvironmentSwitcher`，且 `DebugTestingPanel` 结构体整体在 `#if DEBUG` 内。**发布版不存在** | 读码核实 | — |
| — | 设置入口层级 | — | **保留在首页 header，不下沉** | ① 实名认证 / 紧急联系人补齐入口都在设置里，是 gate 拦截后唯一出路；② WCAG 3.2.6 要求帮助机制位置一致 | `[A]` |

**焦点数变化**：无订单态 10 → 5；有订单态 10-11 → 6。

> **反方提醒（必须一并记录）**：100 名盲人挫折日记研究中，**排名第一的挫折源是「页面布局导致读屏反馈混乱」，
> 不是「元素太多」** `[C]` [ResearchGate 220302591](https://www.researchgate.net/publication/220302591)。
> 减焦点不等于减混乱。**上表所有「合并」动作都必须在真机 VoiceOver 上验证合并后的朗读文本是否仍然可懂** ——
> 合并不当会产出一长串糊在一起的读音，比拆开更糟。

### 4.3 二态方案的论证

**产品方倾向**：无订单 = 只有一个「开始约跑」；有订单 = 首页直接就是订单进行页，**不再展示下单入口**。

**裁决：支持「订单卡占据第 1 焦点」，反对「整页接管、下单入口消失」。**

| 产品 | 有进行中任务时首页形态 | 整页接管？ | 来源 |
|---|---|---|---|
| Uber Eats | 首页顶部绿色横幅，点击进追踪；**首页本身保留** | **否** | `[A]` [Uber Help](https://help.uber.com/en/ubereats/restaurants/article/check-the-status-of-my-order-?nodeId=4148ea8b-c9d8-409d-b7bf-b2fcb019a498) |
| DoorDash | 追踪在 Orders tab；**DoubleDash 在原订单进行中弹窗推荐再下一单** | **否，且明确支持并发下单** | `[A]` [Help](https://help.doordash.com/en-us/consumers/article/can-i-order-from-different-restaurants-at-the-same-time) · `[B]` [TechCrunch](https://techcrunch.com/2021/08/05/with-doubledash-doordash-users-can-tack-on-multiple-orders-without-additional-fees/) |
| Grab | 官方称用户「下单后不断重新打开 App 只为看状态」，故做 Live Activities —— **目标是让人不必回 App** | 反向 | `[A]` [Grab 官方博客](https://www.grab.com/inside-grab/stories/live-activities-grab-lock-screen-ios-apple/) |
| Uber（打车） | 2023 改版「简化首页 + Services tab」；行程进度主推 Live Activity / 灵动岛 | 未找到首页被替换的证据 | `[A]` [Uber Newsroom](https://www.uber.com/us/en/newsroom/were-redesigning-the-uber-app-just-for-you/) |
| 美团外卖 | 下单后右下角常驻悬浮窗，**同时出现在首页/订单/我的三个 tab** | **否** | `[D]` [人人都是产品经理](https://www.woshipm.com/evaluating/1629802.html)（约 2018，形态或已迭代） |
| 滴滴 / Lyft / Bolt / 曹操代驾 | **未找到证据** | — | — |

**正证据（支持订单占据最显著位置）**：Grab 官方明确写用户「下单后不断重新打开 App，就是为了看行程和配送状态」`[A]`。
Uber Eats 把它做成首页顶部横幅 `[A]`。

**反证（反对下单入口消失）**：
1. DoorDash 的 DoubleDash 是因为观察到「顾客点完餐后 30 分钟内又下第二单」才做出来的 `[B]`。
   **整页接管会直接杀死这类行为。** AidRun 的等价场景：盲人在等本周三的陪跑时想顺手约下周的。
2. NN/g 的模式论：「有订单时 App 完全变样」是一个**强模式**，模式滑错的根因是系统未清晰指示当前状态
   `[C]` [NN/g Modes](https://www.nngroup.com/articles/modes/)。**依赖记忆序列的盲人用户尤其容易滑错。**

**未找到证据**：任何 NN/g / Baymard / Apple HIG / Material Design **直接讨论「单一进行中任务是否应接管首页」**
的条目 —— 这个问题在公开设计规范里没有被点名回答。也未找到「首页被订单接管导致用户找不到别的功能」的直接实证。

**建议形态**：

1. 有订单时，订单状态卡是**第 1 个可聚焦元素**，进页面自动 `Announcement(.high)` 播报当前状态。
   对 VoiceOver 用户，这在功能上**已经等于接管**。
2. 下单入口、订单历史保留但**下沉到二级**，**不得从无障碍树移除**。
3. **加 Live Activity + 灵动岛** —— 这是 Apple、Grab、Uber、e代驾共同给出的答案 `[A]`。
   Apple HIG 明确 Live Activity 用于「有明确开始和结束」的活动，出现在锁屏/灵动岛/StandBy 等**一瞥即得**的位置
   `[A]` [HIG Live Activities](https://developer.apple.com/design/human-interface-guidelines/live-activities/)。
   **这是对盲人最大的一条**：不必解锁进 App 就能听到状态。
4. 无论哪种形态，**取消 / 联系志愿者 / 求助（`IN_PROGRESS` 时）必须在首屏两次滑动内可达**。

---

## 5. 交互范式裁决

**被审查的假设**：
> 不做「简易/完整模式」开关，靠减法 —— 首页只留一个占屏幕大半的主操作，它既是低视力用户一眼可见的大按钮，
> 又是 VoiceOver 的第 1 个焦点；再用 Magic Tap 作为熟练用户的加速键。焦点从 8 降到 2-3，熟练用户不会退化。

| 分句 | 裁决 | 关键证据 |
|---|---|---|
| 「占屏幕大半的主操作」对 **B 类**有效 | **证实** | WCAG 2.5.5 Understanding 明确 low vision 为受益群体并附实证引用 `[A]`；Parhi / Kobayashi / Leitão 的尺寸-错误率曲线 `[C]` |
| 「占屏幕大半的主操作」对 **A 类**有效 | **证伪** | VoiceOver 选中元素后**可在屏幕任意位置双击激活，物理面积不影响激活** `[A]` [Orange a11y 指南](https://a11y-guidelines.orange.com/en/mobile/ios/voiceover/)；WCAG 2.5.5 的首要受益者是**运动障碍**用户 `[A]` |
| 「它是 VoiceOver 的第 1 个焦点」 | **证实且应强化** | WCAG 2.4.3 / GB/T 37668 3.3.3.6（**一级**）`[A]`。这才是真正的杠杆，不是尺寸 |
| 「焦点从 8 降到 2-3」 | **部分证伪** | ① 目标不可达 —— 项目硬规则（重复当前状态、位置摘要作为地图文字等价物）就占掉 2 个，现实下限是 **5**；② **减焦点是否真的省时间 —— 未找到任何把 VoiceOver 遍历时间对元素数量做回归的研究**，这条产品方与反方都缺证据；③ 盲人挫折日记里排名第一的是「布局导致读屏反馈混乱」，不是元素多 `[C]` |
| 「不做简易/完整模式」 | **证实**，但产品方误读了理由 | WebAIM 对 ADA NPRM 的回应：**45.4% 读屏用户「很少或从不」使用 text-only/读屏专版**，且使用率持续下降；"separate but equal 在数字环境中很少被证明成立" `[B]` [WebAIM](https://webaim.org/blog/response-to-ada-nprm/)。国内案例：**全民 K 歌关怀模式砍掉推荐/关注/直播/合唱只留点歌，受访老人因此主动退回普通模式** `[B]` [澎湃](https://www.thepaper.cn/newsDetail_forward_24096547) |
| **但**「不做模式开关」≠「不做可配置」 | **产品方可能错在这里** | a11y 社区反对的是**「另做一个残缺的独立版本」**，不是反对同一界面内的详略可配置。W3C 甚至**允许** conforming alternate version 作为达标路径 `[A]` [WCAG 2.2 Conformance](https://www.w3.org/WAI/WCAG22/Understanding/conformance)。而**盲人交通 App 焦点小组把「可配置性」列为最想要的特性之一** `[C]` [NSF PAR 10063454](https://par.nsf.gov//servlets/purl/10063454)。**建议：保留一个「播报详略」开关放在设置里，不放首页，不叫「简易模式」** |
| 「Magic Tap 作为加速键，熟练用户不退化」 | **强证伪** | ① **它不是你的按键**：用户可在 设置>辅助功能>VoiceOver>命令>触摸手势 把两指双击整个重映射 `[D]` [AppleVis](https://www.applevis.com/forum/ios-ipados/there-way-prevent-magic-tap-launching-music-playback-when-not-music-app)；② **误触是常态**，AppleVis 专门出过一期播客教用户「驯服 Magic Tap」`[D]` [播客](https://www.applevis.com/podcasts/taming-magic-tap-stop-accidental-media-playback-ios)；③ **iOS/iPadOS 26 起新增了可关闭的开关** `[B]` [AFB](https://afb.org/blog/entry/ios-26-accessibility-features)；④ 系统冲突真实存在：无实现时沿响应链回落到系统媒体播放 `[A]`；⑤ **第三方采用率极低** `[D]` [Create with Swift](https://www.createwithswift.com/preparing-your-app-for-voiceover-magictap/)；⑥ Smaradottir 2018（6 名视障参与者）报告最难的两个手势之一是两指双击 `[C]` [Hindawi](https://www.hindawi.com/journals/misy/2018/6941631/)（该条为搜索摘要转述，**全文未核到**）；⑦ Apple HIG 本身要求核心功能有一条以上交互路径 `[A]` |

### 裁决：假设**部分成立**，但必须换掉两根支柱

**换掉支柱 1：** 把「大按钮」的正当性从「服务全盲用户」改为「服务低视力用户 + 满足 WCAG 2.5.5 AAA」。
**不要用它论证 A 类的效率收益** —— 那是不成立的。

**换掉支柱 2：** 把「熟练用户不退化」的兜底从 **Magic Tap** 换成 **App Shortcuts（iOS 16+）**：

- 可编程、可从锁屏与 AirPods 发起、不冒泡到系统行为、不被用户重映射掉 `[A]`
- 有两个直接同行先例：Be My Eyes 的免配置 `"Hey Siri, make a call with Be My Eyes"` `[A]`、
  小艾帮帮的「使用小艾帮帮呼叫志愿者」`[B]`
- **建议注册两条**：「用助盲跑约跑」（进语音下单）与「助盲跑现在什么情况」（播报当前订单状态）
- **红线：SOS 不得注册为 Siri 快捷指令**（绕过 `AGENTS.md` 第 6 节的逐字二次确认）

**若仍要做 Magic Tap**：必须挂在 **App 根视图**（否则其他页面冒泡到系统播放音乐）、返回 `true` 阻断响应链、
真机验证、且**不承担任何独占功能**。它只能是锦上添花的第二路径。

---

## 6. 语音预约完整交互契约

> 每节点格式：**触发条件 → 系统反馈（听觉 / 触觉 / 视觉）→ 超时值 → 失败降级路径**。
> 「现状」列来自读码，行号可核。

### 6.1 唤起

| 项 | 建议 | 现状 | 依据 |
|---|---|---|---|
| 触发 | 按「开始约跑」，或 App Shortcut | `.voiceBooking` 路由 → `BlindBookingView(startsWithVoice: true)`（`:401-409`） | — |
| 听觉 | **两个音色可区分的 earcon**：起音（Start of Request）与收音结束（End of Request）。Alexa 的 "attention system" 明文要求音频与视觉线索同步 | ~~未实现~~ **已实现**（2026-08-06 复核）：`RecordingCue`（`SpeechInputService.swift:75-88`）起 1113 / 止 1114，调用点 `:458` / `:343` | `[A]` [Invoking Alexa](https://developer.amazon.com/en-GB/docs/alexa/alexa-auto/invoking-alexa.html) |
| 触觉 | `UIImpactFeedbackGenerator`，起止各一次 | ~~未实现~~ **已实现**：起用 `.light` impact、止用 `.success` notification（语义分工见 `:64-74` 注释） | `[A]` 同上 |
| 视觉 | 录音指示动画，闪烁 ≤3 次/秒，`accessibilityReduceMotion` 时降级为静态 | spec.md:100-104 已写入 | `[A]` WCAG 2.3.1 |
| 延迟容忍 | **≤100 ms 播 earcon 并开麦；>1 s 未就绪必须播「正在准备」占位语音，不许静默等待** | `speechSettleTimeout = 8s`（等 TTS 播完再开麦，`VoiceOrderWizard.swift:75`）—— **8 秒静默窗口是缺陷** | **未找到任何平台的官方毫秒规定。** 唯一可引的是 Nielsen 三档 0.1 / 1.0 / 10 s `[C]` [NN/g](https://www.nngroup.com/articles/response-times-3-important-limits/) |
| 降级 | 麦克风/识别授权被拒 → 立即一次性播报原因 + 进表单，**不进重问循环** | **已实现**：`isSpeechPathUnavailable`（`SpeechInputService`）+ `clearRecognitionStartState` 送出 `.error` 终局完成 | 提案任务 1.1-1.7，已真机跑通 |

**国内唯一逐字实例**（申程出行智慧屏刷脸叫车）`[A]`：
> 点击「刷脸叫车」→ 跟随语音提示「**面向屏幕，开始刷脸**」→ 识别成功后核对个人信息并点击「**确认**」按钮

线下扬招杆呼叫后屏显：「**正在呼叫，请耐心等待**」。
另：美团打车「助老打车」**打开该选项时即语音播报操作提示** `[D]` —— 这是「进入即播，不等用户触发」的先例，
与 `docs/09` 已有的「进入盲人首页必须播报」一致。

### 6.2 采集 / 尾静音阈值 —— **最需要改的一节**

| 平台 | 尾静音默认 / 范围 | 首次静音超时 | 来源 |
|---|---|---|---|
| **Azure Speech** | `Speech_SegmentationSilenceTimeoutMs` **100-5000 ms，典型默认 500 ms** | `InitialSilenceTimeoutMs`：单次 5000 ms / 连续 15000 ms | `[A]` [MS Learn](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/how-to-recognize-speech) |
| **Dialogflow CX** | `endpointer_sensitivity` 0-100（**默认值文档未给**）；smart endpointing 仅 en-US 且默认关闭 | no-speech timeout **默认 5 s，最大 60 s** | `[A]` [Advanced speech settings](https://docs.cloud.google.com/dialogflow/cx/docs/concept/advanced-speech) |
| **Apple `SFSpeechRecognizer`** | **不暴露任何 end-silence 属性**，需自建定时器 | 单次音频约 60 s 上限 | `[D]` [Apple Forums 82839](https://developer.apple.com/forums/thread/82839)（Apple 官方论坛，非文档） |
| **Web Speech API** | **规范未提供任何可调静音阈值** | — | `[A]` [MDN](https://developer.mozilla.org/en-US/docs/Web/API/Web_Speech_API/Using_the_Web_Speech_API) |
| **Alexa Skills Kit** | **不公开、不可配置**，文档只写 "a few seconds" | — | `[A]` [Manage Skill Sessions](https://developer.amazon.com/en-US/docs/alexa/custom-skills/manage-skill-session-and-session-attributes.html) |
| **AidRun 现状** | `voiceOrderFreeform` **12 s**；其余 field 3 s（`SpeechInputService.swift:551-553`） | freeform **15 s**；其余 8 s（`:547-549`） | 读码 |

**人类说话停顿的实证**：

- 句内静默停顿经典下限 **200 ms**；停顿时长呈**对数正态**，自发语音三峰聚在
  约 **150 ms / 500 ms / 1500 ms**（Campione & Véronis 2002 三高斯混合）
  `[C]` [MDPI Languages 8(1):23 综述](https://www.mdpi.com/2226-471X/8/1/23)
- 说话人间换手间隙**模态约 200 ms**，10 语言中位数 0-300 ms
  `[C]` [Stivers et al., PNAS 2009](https://www.pnas.org/doi/10.1073/pnas.0903616106)

**裁决**：

| 取值 | 判定 |
|---|---|
| **500 ms**（Azure 默认） | 对复合长句**过短** —— 会在句内 1500 ms 模态的停顿处把「明天下午三点，从…」切断 |
| **3 s**（项目其余 field） | 落在自发语音最长停顿模态（1500 ms）之外一倍，用户会在系统还在等时以为「没听见」而重复说，制造 **overcapture** |
| **12 s**（项目 freeform 现值） | **明显过长**。超 Nielsen 的 10 s 注意力上限 `[C]`，是 Dialogflow no-speech 默认值的 2.4 倍 `[A]`。看不见屏幕的人会判定为死机 |
| **建议 2000 ms** | 覆盖第三模态（1500 ms）留 500 ms 余量，且远在「以为死机」区之外。**这是推导值，不是任一文档的默认值** |

**并且必须同时提供显式结束通道** —— 纯静音兜底在任何取值下都会牺牲一部分用户：

1. **整块内容区可点击结束**（提案 spec.md:96 已要求，标为「说完了」并给 label）
2. **加一条语音结束词**：说「说完了 / 好了 / 就这些」立即收音。行业先例是 Dialogflow CX 的 smart endpointing ——
   分析部分转写决定是否继续等，并提供 waiting timeout 宽限期 `[A]`
3. 首次静音超时（无人说话）保持 8 s 后播「没有听到你说话，请再说一次」

> **未找到证据**：Alexa 收音窗口的确切秒数（Amazon **刻意不公开、不可配置**，社区流传的「8 秒」无官方出处）；
> Azure `Speech_SegmentationMaximumTimeMs` 与 Dialogflow `endpointer_sensitivity` 的默认值（文档给属性不给数字）。

### 6.3 读回

| 项 | 建议 | 现状 | 依据 |
|---|---|---|---|
| **必须重述全部槽位** | 是 | **已做** —— `confirmPrompt(for:)` 三段：用户原话 + 整单 + 两条出路（`docs/09:24` 已锁定） | Alexa `Dialog.ConfirmIntent` 明文："be sure to **repeat back all values** the user needs to confirm" `[A]` [Dialog Interface](https://developer.amazon.com/en-US/docs/alexa/custom-skills/dialog-interface-reference.html) |
| **必须念解析结果，不是 ASR 原文** | 是 | **已做**（整单段是解析后的地点名/绝对时间/时长），且**额外**念了原话 —— 项目的三段式在这一点上比 Alexa 规范更强 | 语音购物失败的根因即「确认步骤只回读转写文本而非解析后的商品」`[C]` [CHI'23](https://dl.acm.org/doi/fullHtml/10.1145/3544548.3581152) |
| 顺序 | 固定为「时间 → 地点 → 时长」 | 现为「起点 → 时间 → 选填」（`spec.md:21`） | 无外部规范，**推导**：时间是最易错且最不可逆的槽位，应先念 |
| 长度 | ≤10 s | 三段式实测长度未测 | **未找到任何官方字数/秒数上限。** Alexa 侧最接近的是非规范的 "one-breath test" `[C]` |
| **barge-in（打断读回）** | **整单读回段允许打断；「说『确认』就下单」那句锁为 no-barge-in** | **未实现** —— `waitForSpeechToSettle` 是等 TTS 播完才开麦，中间无法打断 | Alexa 车载："customers **must be able to interrupt** Alexa" `[A]`；Dialogflow CX `BargeInConfig` 把播报显式拆成 no-barge-in phase + barge-in phase `[A]` [BargeInConfig](https://docs.cloud.google.com/ruby/docs/reference/google-cloud-dialogflow-cx-v3/latest/Google-Cloud-Dialogflow-CX-V3-BargeInConfig) |
| 时长取整提示 | 必须与读回**拼成同一段** | **已做**（`moveToConfirm(notice:)`，`docs/09:25`）—— 这是真机测试暴露出来的，分两次播会让「重复一遍」念不到 | 项目实测 |

> **barge-in 是本节唯一的实质缺口。** 三段式读回约 10 秒，听第一遍即知道要改时长的用户必须干等到底。
> 但注意：加 barge-in 会与「起止 earcon」的音频会话切换时序冲突，实现成本不低 —— 建议列为独立后续项，
> 不塞进当前批次。

### 6.4 确认词白名单 —— **本报告最硬的一条改动建议**

**硬要求**：

- Google 明文：explicit confirmation 保留给「**难以撤销的动作，例如删除用户数据、完成一笔交易**」
  `[A]` [Google Confirmations](https://developers.google.com/assistant/conversation-design/confirmations)
- Apple HIG Siri：「某些任务如**发消息和支付永远需要确认**」`[A]` [HIG Siri](https://developer.apple.com/design/human-interface-guidelines/siri)
- **WCAG 3.3.4（AA）**：产生法律承诺或财务交易的提交，必须满足**可撤销 / 已校验 / 可复核确认**三者之一 `[A]`

→ 项目同时满足「可复核确认」（读回 + 显式肯定）与「可撤销」（`canBlindRunnerCancel`）。**合规无问题。**

**但白名单本身有严重问题。** 现状 19 条（`VoiceOrderWizard.swift:598-603`）：

```
确认 确定 确认下单 确认预约 确认提交
好 好的 行 可以 对 是
没问题 没错 同意 就这样 就这么办
提交 下单 开始约跑
```

**证据链**：2018-05 Portland 事件，Amazon **官方复盘**的失败链条是 ——
背景对话被识别为唤醒词 → 被识别为发消息请求 → Alexa 问 "To whom?" → 背景对话被识别为联系人名 →
Alexa 问 "[名字], right?" → **背景对话被识别为 "right"** → 私人对话录音被发给通讯录联系人。
`[B]` [CBS News](https://www.cbsnews.com/news/amazon-alexa-echo-device-recorded-conversation-sent-to-contact/) ·
`[D]` [WWeek](https://www.wweek.com/news/2018/05/26/portland-family-says-their-amazon-alexa-recorded-private-conversations-and-sent-them-to-a-random-contact-in-seattle/)

**这是一个短确认词被环境语音满足、完成不可撤销动作的完整证据链。**
另一条：2017-01 Alexa 玩具屋误单后，圣地亚哥电视台主播在新闻中复述该句，**触发观众家中 Echo 尝试下单**
`[B]` [CBS](https://www.cbsnews.com/news/tv-news-anchors-report-accidentally-sets-off-viewers-amazons-echo-dots) ·
`[C]` [Snopes 复核](https://www.snopes.com/fact-check/alexa-orders-dollhouse-and-cookies/)。

**中文的「对」「行」「好」「是」与英文 "right" 完全同构。** 且 AidRun 有一个 Alexa 没有的加重因素：
**陪跑场景下志愿者可能就在旁边说话**，「好」「行」「对」是中文日常对话里频率最高的应答词。

**建议白名单（收窄到 8 条，全部 ≥3 音节或语义不可能出现在闲聊应答里）**：

```
确认下单  确认预约  确认提交  确认
就这样    就这么办  没问题    开始约跑
```

**建议删除**：`好` `好的` `行` `可以` `对` `是` `没错` `同意` `提交` `下单` `确定`
- 前 8 个是单/双音节高频应答词，Portland 同构
- `提交` `下单` 是名词性动词，在「我要下单」「帮我提交一下」等叙述里会命中
- `确定` 保留与否可讨论 —— 它是双音节但语义专用，风险中等

**收窄的代价与收益**：`design.md` 决策 2 已经正确论证了方向性不对称 ——
「确认」被误判为「非确认」用户多说两轮（可恢复）；「修改」被误判为「确认」产生真实派单（代价高）。
**收窄白名单正是这条论证的自然结论，现状的 19 条与该论证不一致。**

**必须同时做的三件事**：
1. **读回的出路那句必须明确念出该说什么** —— 现状念的是「说『确认』就下单」，
   收窄后必须保持这句与白名单一致（否则用户说了系统教他说的词却不生效）
2. 单测逐条锁定 8 条白名单 + 现有的 13 条「含肯定词的否定」用例（`testNegationsContainingAffirmativeWordsAreNotConfirmation` 已存在）
3. **补一条「环境语音」用例**：模拟转录为「好啊我知道了」「对了你等一下」这类含肯定词的闲聊，断言不提交

> **未找到证据**：**中文 ASR 确认词的混淆率**。没有找到任何论文报告「对/不对」「是/不是」的具体混淆矩阵。
> 只找到定性证据 ——「不」为短促常弱读音节易被吞并，中文单字脱离上下文识别极不可靠。
> ASR-EC 基准 `[C]` [arXiv 2412.03075](https://arxiv.org/html/2412.03075v1) 可作后续自测语料，但不提供该数字。
> **建议项目自行采集黄金语料实测，不要引用任何二手数字。** 仓库已有 `scripts/validate-golden-corpus.mjs`，是现成的落点。

### 6.5 纠错（定点修改）

**行业做法是意图 + 槽位，不是关键词整串匹配。** Alexa 提供 `Dialog.ElicitSlot` / `Dialog.ConfirmSlot`
**按槽位定点重问**而非重来整句，`confirmationStatus` 三态 NONE / CONFIRMED / DENIED `[A]`。

**现状**：本地关键词整串匹配，三组词表（`VoiceOrderWizard.swift:605-619`）：
- 地点 8 词：`改地点 修改地点 换地点 换个地点 改出发地 改出发地点 地点 改地址`
- 时间 7 词：`改时间 修改时间 换时间 换个时间 改出发时间 时间 改几点`
- 时长 7 词：`改时长 修改时长 换时长 改跑多久 时长 改多久 改时间长度`

**裁决：维持关键词匹配，不引入意图识别。** 理由与 `design.md` 决策 1 一致 ——
这是高精度识别问题不是高召回分类问题，且不新增后端调用、无网络往返、无超时窗口。

**但有两个具体问题**：

1. **单字「地点」「时间」「时长」在白名单里，与 §6.4 的收窄逻辑矛盾。**
   用户说「时间不用改」会命中吗？—— 不会，因为是**整串匹配**（先经 `normalizedCommand` 去标点与句尾语气词）。
   整串「时间不用改」≠「时间」。**这一点现状是安全的，值得记录下来防止后续有人改成包含匹配。**
2. **纠错后不支持连续修改的确认。** 现状：改完回 `.confirm` 重念整单（`:425/436/447`），正确。

### 6.6 失败降级

| 失败类型 | 正确降级路径 | 现状 |
|---|---|---|
| 麦克风/语音识别授权被拒 | **一次性播报原因 + 立即进表单，不进重问循环** | **已实现**（`isSpeechPathUnavailable` + `clearRecognitionStartState` 终局回调） |
| recognizer 不可用 / 音频会话失败 | 同上 | 已实现 |
| 识别为空 / 听不清 | 重问，**上限 3 次尝试** | `maximumReasksPerSlot = 3`，实际重问 2 次第 3 次降级（`:535-544`）。**合规** |
| 解析 API 超时 | 重问并计入重问上限 | 已实现（`spec.md:126`） |
| 解析 API 层失败（非超时） | **降级到表单并播报原因，不重问** | 已实现（`spec.md:124-125`）—— 这条是真机测试暴露出来的，`try?` 曾把它抹平成重问 |
| **嘈杂环境识别错误** | **无专门路径** | **缺口**，见下 |

**重试上限依据**：Google 明文「用户连续经历的 No Input / No Match 错误**不应超过 3 次**」，
之后播 max error prompt 并退出；重试文案用 rapid reprompt（道歉 + 精简复述问题），
「第 1 次 No Match 默认不升级细节」，**例子比解释有效**
`[A]` [Google Errors](https://developers.google.com/assistant/conversation-design/errors)。
→ 建议第 1 次「没听清，请再说一遍」；**第 2 次给范例句**（项目 `.freeform` 提问已含范例
「明天早上八点从人民广场出发跑一个小时」，重问时应复用）；第 3 次给出口。

**嘈杂环境缺口**：每降 5 dB SNR 错误率约翻倍，10 dB（嘈杂街道/餐厅）WER 约 15-20%，10 dB 以下急剧劣化
`[C]` [Springer 2026](https://link.springer.com/article/10.1186/s13636-026-00458-1)。
**国内的主流答案不是「重试识别」，而是「绕过识别」** `[D]`：
1. 人工代叫热线（滴滴 4006881700、曹操 400-608-1111、全国 95128 覆盖 280+ 城市）
2. **免输入**：一键叫车不输起终点
3. **语音消息转发不做 ASR**：宜兴「阳羡行」可**直接发送语音消息告知司机目的地，讲方言也能下单**
4. 亲情账号代叫代付

→ **AidRun 的可行等价物**：第 3 次失败后，除了进表单，还应提供「**用常用出发点 + 最早可约时间直接下单**」
这条零输入路径（§1.1 已论证常用出发点的价值）。

**红线（提案已写入，必须保住）**：每一次语音下单尝试都必须抵达一个**用户听得见**的终局，
不得停在 `isRunning = true` 且无待答提示的静默态（`spec.md:106-121`）。

### 6.7 成单后播报

**建议**：只播「已下单」+ 关键锚点，≤5 s，细节留给「重复当前状态」。
依据：Google 的 implicit confirmation 用于「确认动作已完成（除非不言自明）」`[A]`。

**现状**：`docs/09:150` 定的是 `PENDING_MATCH` 文案「订单提交成功，系统正在为你派单。」—— 长度合适。

**建议补一句锚点**（推导，无外部规范支撑）：「订单提交成功，系统正在为你派单。要取消可以在首页说……」
—— 因为 WCAG 3.3.4 的「可撤销」若用户不知道怎么撤销，等于不存在。

---

## 7. 前置 gate 的时机建议

### 7.1 现状（读码核实，与任务书的描述有一处出入）

6 道 gate 定义在 `BlindBookingView.swift:112-119`，顺序即播报优先级（注释明确要求与后端
`OrderCreationService.createOrder` 同序）：

| gate | 判定 |
|---|---|
| `basicProfile` | `appState.isBlindBasicProfileComplete` |
| `identityVerification` | `appState.isBlindIdentityVerified` |
| `emergencyContacts` | `appState.hasValidEmergencyContacts` |
| `locationPermission` | `locationService.isDenied` |
| `startPoint` | `resolvedStartPlace != nil` |
| `appointmentTime` | `isAppointmentTimeValid` |

**重要事实修正**：拦截时机**两条路径不同** ——

- **语音路径**：`VoiceOrderWizard.swift:141-145` 在 `start()` 前就拦，跳过 `.startPoint` / `.appointmentTime`
  两道（它们是槽位，向导自己会填），其余四道直接 `fallbackMessage` + 播报。**时机正确。**
- **表单路径**：前 3 道 gate **不在** `blockingReasonForCurrentStep`（`:224-250`）里，
  因此分步向导过程中不拦截，**只在最终 `submit()`（`:612-617`）才暴露**。
  → **用户填完 4 步表单、点提交，才被告知「请先添加紧急联系人」。这是最坏的失败时机。**

### 7.2 行业惯例

| gate | 行业惯例时机 | 依据 |
|---|---|---|
| 基本资料 | **尽量后置**。强制建账号是转化第二大可修复杀手（25% 弃单归因于「被要求注册」）；Baymard 建议把建账号推到确认页 | `[C]` [Baymard](https://baymard.com/blog/delayed-account-creation) |
| 实名认证 / KYC | **分层 / just-in-time**：注册只收轻量信息，完整 KYC 推到首次交易前 | `[D]` [Sardine](https://www.sardine.ai/blog/kyc-conversion-rates)（厂商博客，有商业利益偏向） |
| **紧急联系人** | **同类产品一律不在注册强制**：Uber Trusted Contacts 在 Settings / Safety Toolkit 手动设置；Life360 在 Safety tab 下**独立的 "Begin Setup" 引导流**；Apple 医疗急救卡在 Health App 内 | `[A]` [Uber](https://www.uber.com/za/en/ride/safety/rider-safety-features) · [Life360](https://support.life360.com/hc/en-us/articles/23053433936151-Life360-Emergency-Contacts) · [Apple](https://support.apple.com/en-us/105072) |
| 定位权限 | **用到时再要**；仅当定位是 App 核心功能时启动即要才可接受 | `[A]` [Apple HIG](https://developer.apple.com/design/human-interface-guidelines/patterns/accessing-private-data/) · `[C]` [NN/g](https://www.nngroup.com/articles/permission-requests/) |
| 出发地点 / 预约时间 | 任务输入，下单流程内分步采集 | `[C]` [NN/g Progressive Disclosure](https://www.nngroup.com/articles/progressive-disclosure/) |

**视障用户长表单的实证代价**（这是本节最重要的数据）：

- Fortune 500 求职表单研究：3 名盲人熟练屏读用户对 30 个站点共 90 次尝试，**成功率仅 55.6%**，
  完成时间 **20 分钟到 2 小时 15 分**（普通用户通常「不到 5 分钟」）；30 个站点中 **76.7%** 至少阻断了一名测试者；
  **日期选择器与组合控件占阻断问题的 34%** `[C]` [PMC10961918](https://pmc.ncbi.nlm.nih.gov/articles/PMC10961918/)
- 屏读用户完成任务耗时是视力用户的 **2.28 倍**（211 s vs 92 s，p<0.0001）`[C]` [arXiv A11y-CUA](https://arxiv.org/pdf/2602.09310)
- **69%** 残障网购者会因难用直接离开站点 `[C]` [Click-Away Pound 2019](https://www.clickawaypound.com/)

> **注意「日期选择器占阻断问题 34%」这一条对本项目的直接冲击**：`docs/09:104` 明确「Appointment time
> remains `DatePicker`」，`spec.md:50` 也要求手动修改时间时用系统 `DatePicker`。
> 这条规则在表单路径上正踩在最高危控件上。**语音路径绕开了它，这是语音优先最实在的收益之一** ——
> 比「少几个焦点」的收益扎实得多。

**未找到证据**：视障用户在**原生移动 App** 长表单上的完成率/弃用率/每字段耗时 —— 现有数据全部是 Web 场景。
WebAIM Survey #10 报告表单障碍类型，但不含完成率或每字段耗时
`[C]` [WebAIM Survey #10](https://webaim.org/projects/screenreadersurvey10/)。

### 7.3 建议（紧急联系人红线下）

| gate | 建议时机 | 依据 |
|---|---|---|
| **基本资料** | 注册后**引导流**内采集，字段砍到 SOS 与派单真正必需的最小集 | Baymard `[C]` + 视障 2.28× 耗时与 55.6% 表单成功率 `[C]` —— 每多一个字段的代价被放大 |
| **实名认证** | **不放注册，放首次下单前的一次性引导**，且必须是「三分钟内出结果」的即时通道 | 分层 KYC 惯例 `[D]` + 表单弃用数据 `[C]`。**⚠️ 中国大陆是否对本类服务有实名法定要求，未找到可核查的法规条文 —— 需产品/法务确认，不能只按转化率决定** |
| **紧急联系人（红线内）** | **注册后立即进入独立的「求助功能设置」引导流**（含试听一次求助播报），**软引导可跳过**；**下单时保持硬拦截**并给出可听的补齐入口 | **行业无直接先例** —— Uber / Life360 / Apple 三家都是可选、事后、在设置里 `[A]`。最接近的是 **Life360 的独立引导流 "Begin Setup" + "Practice SOS"** `[A]`：不是注册的一部分，但是一个**有明确安全叙事的专属引导**。照此做既不把它塞进注册表单，又保住 SOS 依赖 |
| **定位权限** | 下单流程内、首次需要位置时请求，配 pre-prompt 说明「用于把你的位置发给志愿者和求助时定位」 | Apple HIG 明确「理想情况是等到用户使用需要该数据的功能时再请求」，仅当定位是 App 存在理由时才可启动即请求 `[A]`。本产品定位确实是核心，**启动即请求不违规**，但 pre-prompt 带理由的收益（NN/g 引研究称 +12%，带明确收益说明 +81%）是免费的 `[C]` |
| **出发地点** | 下单流程内，**且提供常用出发点一键选择** | 滴滴关怀版预存 10 个常用地址把「输入目的地」整个消掉 `[D]`；这是 §1.1 已论证的最高杠杆项 |
| **预约时间** | 下单流程内，默认给合法值让用户只需确认 | **已实现**：`configure` 把 `appointmentTime` 抬到 `minimumAppointmentTime + 60`（`BlindBookingView.swift:382-384`） |

**必须修的一个缺陷（与时机无关，是位置问题）**：
表单路径的前 3 道 gate 应从 `submit()` 前移到**进入预约页时**即检查并播报
（语音路径已在 `VoiceOrderWizard.swift:141-145` 做对了）。
现状让用户填完 4 步才被拦，直接违反 WCAG 3.3.7 Redundant Entry 的精神，且对视障用户的代价按 2.28× 放大。

---

## 8. 对 `enable-one-utterance-booking` 提案的逐条审查

| # | 提案条目 | 裁决 | 依据 |
|---|---|---|---|
| 1 | 语音下单改为「一次说完 → 读回整单 → 说确认成单」 | **支持** | WCAG 3.3.4 AA 的三个出路满足了两个（可复核确认 + 可撤销）`[A]`；Alexa `ConfirmIntent` 要求重述全部值 `[A]`。且**跳过确认的纯语音执行有明确翻车模式** `[C]` |
| 2 | 整句抽三槽位，抽不出的用默认值，不重问不失败 | **支持，但有条件** | 一句多意图会让整体准确率崩塌（MixATIS：slot F1 94.3 但 **overall accuracy 仅 60.2**）`[C]` [AGIF](https://arxiv.org/pdf/2004.10087)；错误恰好集中在实体槽位上 `[C]` [Speech2Slot](https://arxiv.org/abs/2105.04719)。**读回是唯一防线，因此读回必须念解析值** —— 项目已做对 |
| 3 | **地点也从整句抽（2026-08-04 起）** | **支持实现，但 spec 文件必须修** | ⚠️ **`specs/blind-runner-voice-first-experience/spec.md:13-17` 仍写着「Start place is NOT extracted from the full utterance」并要求不把整句送 address-resolution。`proposal.md:12` 与 `tasks.md:2A.2` 说该开关已删除、地点已从整句抽。spec 与实现相反。** `openspec validate` 抓不到这类语义漂移 |
| 4 | 定点修改「改地点/改时间/改时长」，本地关键词整串匹配 | **支持** | 行业用槽位定点重问而非重来整句 `[A]`；`design.md` 决策 1 的「高精度而非高召回」论证成立。整串匹配（非包含匹配）是安全的，**应加一条注释防止后人改成包含匹配** |
| 5 | 读回三段式（原话 + 整单 + 出路） | **强支持，且比行业规范更强** | Alexa 只要求重述值；项目额外念原话，正好补上「分不清是自己说错还是系统听错」——这是纯音频复核漏检约 50% ASR 错误的直接缓解 `[C]` [TACCESS 2020](https://dl.acm.org/doi/fullHtml/10.1145/3382039) |
| 6 | 首页下单入口收敛为一个，删 `.booking` 路由 | **支持，已实现** | 读码确认 `BlindRunnerRoute` 只剩 `.voiceBooking`。且 GB/T 37668 3.3.4.2 三级明文要求为文本输入栏提供语音替代 `[A]` |
| 7 | 录音状态可被非视觉感知：起止提示音 + 触觉 | **强支持** | Alexa attention system 的 Start/End of Request 双 earcon `[A]`。~~未实现，应优先做~~ **2026-08-06 复核：已实现**（`RecordingCue`，`SpeechInputService.swift:75-88`），本表与 §5 那两行写于实现落盘之后，属陈旧断言 |
| 8 | **整句尾静音 3 s → 12 s** | **反对，改为 2000 ms** | 12 s 超 Nielsen 10 s 注意力上限 `[C]`，是 Dialogflow no-speech 默认值的 2.4 倍 `[A]`；自发语音停顿第三模态在 1500 ms `[C]`。**且它直接威胁「≤60 秒」判据**（§1.2）。改为 2000 ms + 保留已有的显式结束通道 |
| 9 | 确认白名单 19 条 | **需修正，收窄到 8 条** | Portland 事件是「短确认词被环境语音满足完成不可撤销动作」的官方复盘证据链 `[B]`。**且这与 `design.md` 决策 2 自己的不对称论证不一致** —— 决策写对了，白名单没执行到位。详见 §6.4 |
| 10 | 缺陷修复：`clearRecognitionStartState` 送出 `.error` 终局完成 | **强支持，已实现且真机跑通** | 「每一次尝试必须抵达可听终局」是本提案对盲人端最实质的一条 |
| 11 | 本批次不动首页（`design.md` 决策 5） | **支持这个切分** | 理由成立：首页改动需真机开 VoiceOver 手测，与纯逻辑改动的验证成本差一个量级 |
| 12 | 未完成项 2.10（演示坐标不阻断提交） | **需产品决定，但报告倾向阻断** | `LocationService.isUsingDemoFallback` 只是 `currentLocation == nil` 且**无 DEBUG 门禁**，室内冷启动会返回北京演示坐标。「约到错误起点」对盲人是把人放到陌生地方，与 SOS 的坐标红线同源。**建议至少在语音路径阻断**（语音路径用户看不到屏幕上的警告文字） |
| 13 | 未完成项 2A.8（`missing: ADDRESS` 歧义） | **同意维持「客户端不猜」** | 等后端区分「没说」与「说了抽不出」是对的。读回念出实际起点是有效兜底 |
| 14 | 未完成项 3.4 / 3.5 / 3.7（三条测试未写） | **必须补，且 3.7 优先** | 3.7 是 UI 测试验证首步文案 —— 它是唯一能自动发现「读回三段式退化」的检查 |
| 15 | 未完成项 5.5（真机开 VoiceOver 手测） | **阻塞发布** | `tasks.md` 自己写了「自动化测试跑通不等于语音链路可用：端到端还没有真人对着麦克风说过话」。且生产 `AMAP_WEB_KEY` 未配，地点抽取线上验不了 |

### 新首页架构：合入这个变更，还是另开独立变更？

**建议：另开独立变更 `refocus-blind-runner-home`。** 三条理由：

1. **`design.md` 决策 5 已经给了正确的切分理由，且它现在更成立**：首页改动需真机开 VoiceOver 手测，
   与纯逻辑改动的验证成本差一个量级；混在一起会让真机批跑失败时无法定位是哪一半的问题。
   而 `enable-one-utterance-booking` 现在正卡在 5.5 手测未做上 —— **再往里加东西只会让那次手测更难定位**。
2. **能力边界天然清晰**：
   - `enable-one-utterance-booking` 的 spec 是 `blind-runner-voice-first-experience`，
     已含一条 ADDED Requirement「Booking has exactly one entry point」（`spec.md:68-75`）——
     **它只规定「首页恰好有一个下单动作」，不规定首页还有什么。** 这个边界是对的，不用动。
   - 新变更负责的是**其余 7 个区块的裁决 + VoiceOver 焦点顺序 + 二态**，
     对应一个新能力（建议名 `blind-runner-home-information-architecture`）。
3. **两者不 delta 同一个能力**，符合会话启动提示里「多个未归档变更同时存在时先确认没有 delta 同一能力」的要求。

**新变更的建议范围**（一次一个内聚模块，`AGENTS.md` 第 4 节）：
- 区块合并与焦点裁决（§4.2 表）
- 二态：订单卡提到第 1 焦点 + 下单入口下沉
- 64 pt 改 `@ScaledMetric`（EN 301 549 §11.7）
- 「重试加载」补 64 pt
- 表单路径前 3 道 gate 前移到进页面即检查
- 扩 `AccessibilityAuditTests`：焦点总数上限断言 + 遍历顺序断言（现有审计查不到这两项）

**不放进新变更、应各自独立**：Live Activity（新能力，需契约与产品）、App Shortcuts（新能力）、
常用出发点（需后端契约）、配速/距离槽位（需后端契约）、barge-in（音频会话时序改动，风险独立）。

---

## 9. 反对意见与已知失败模式

### 9.1 「一句话下单」的已知失败案例与批评

| # | 现象 | 触发条件 | 来源 |
|---|---|---|---|
| 1 | **广播/他人说话触发下单**：Alexa 玩具屋误单后电视主播复述该句，触发大量观众家中 Echo 尝试下单 | 免唤醒或宽松确认的语音下单链路 | `[B]` [CBS](https://www.cbsnews.com/news/tv-news-anchors-report-accidentally-sets-off-viewers-amazons-echo-dots) |
| 2 | **短确认词被环境语音满足完成不可撤销动作**（Portland，Amazon 官方复盘） | 单音节确认词 + 背景对话 | `[B]` [CBS](https://www.cbsnews.com/news/amazon-alexa-echo-device-recorded-conversation-sent-to-contact/) |
| 3 | **同音词 ASR 错误在纯音频复核中被漏掉**（英文对照组漏检约 50%） | 语音输入 + TTS 读回、无逐字符复核。**中文地址的同音/近音风险显著更高** | `[C]` [TACCESS 2020](https://dl.acm.org/doi/fullHtml/10.1145/3382039) |
| 4 | **语音输入速度优势被纠错成本吃掉**：盲人语音输入比键盘快近 5 倍，但 **80.3% 的时间花在编辑纠错上** | 盲人用语音输入长文本，缺高效编辑手段 | `[C]` [Azenkot & Lee, ASSETS 2013](https://dl.acm.org/doi/10.1145/2513383.2513440) |
| 5 | **一句多意图导致整句正确率崩塌**（slot F1 94.3 / overall acc 60.2），意图数增加时单调下降 | 单条指令含多个参数 | `[C]` [AGIF](https://arxiv.org/pdf/2004.10087) |
| 6 | **嘈杂环境 WER 数倍上升**（10 dB 约 15-20%，每 −5 dB 翻倍） | 地铁/公交/街边下单 | `[C]` [Springer 2026](https://link.springer.com/article/10.1186/s13636-026-00458-1) |
| 7 | **用户记不住该说什么**（VUI discoverability 是仅次于识别准确率的第二大障碍）；onboarding 命令清单在真正要用时已被遗忘 | 无持续可发现性设计 | `[C]` [ResearchGate 307090834](https://www.researchgate.net/publication/307090834) |
| 8 | **overcapture（多收了用户没打算说的话）对信任的破坏最大**；用户会短期停用出错的那类任务 | 199 例失败语料、12 类失败源 | `[C]` [CHI 2023](https://dl.acm.org/doi/fullHtml/10.1145/3544548.3581152) |
| 9 | **46% 消费者不信任语音助手能正确理解并处理订单**，45% 不信任语音支付 | PwC 消费者调查 | `[D]`（原始 PwC 报告未直接核到，不单独支撑决策） |

**行业侧的间接承认**：阿里云专门提供「语音地址输入识别」后处理链路（语音顺滑 → 地址抽取 → 纠错 → 补齐），
**本身即承认裸 ASR 不足以支撑语音下单** `[A]` [阿里云](https://help.aliyun.com/zh/address-purification/addrpapi/developer-reference/voice-address-recognition)。

### 9.2 极简首页对视障用户的负面影响

| # | 现象 | 来源 |
|---|---|---|
| 1 | **界面状态变化只有视觉信号 → 盲人「知道变了但不知道变成什么」，产生失控感并妨碍建立心智模型** | `[C]` [Open Challenges of Blind People using Smartphones](https://arxiv.org/pdf/1909.09078) |
| 2 | 100 名盲人挫折日记研究中，**排名第一的挫折源是「页面布局导致读屏反馈混乱」，不是元素太多** | `[C]` [ResearchGate 220302591](https://www.researchgate.net/publication/220302591) |
| 3 | 商业语音助手推行的「简洁」规范（如 Amazon 的 one-breath test）**反而损害盲人可访问性**；给出命令清单会「打消实验意愿并剥夺控制感」 | `[C]` [Branham & Roy, ASSETS 2019](https://doi.org/10.1145/3308561.3353797) |
| 4 | 语音助手对盲人「**便利但浅**」：能快速拿到答案，却无法深入内容或给出备选概览 | `[C]` [VERSE, ASSETS 2019](https://dl.acm.org/doi/pdf/10.1145/3308561.3353773) |
| 5 | 国内「关怀模式」砍功能 → 目标用户主动退回普通模式（全民 K 歌案例） | `[B]` [澎湃](https://www.thepaper.cn/newsDetail_forward_24096547) |
| 6 | 信息无障碍研究会实测通病：「**缺少焦点导致无法操作，或焦点冗余导致操作效率低**」——**两个方向都是问题** | `[C]` [capa.run](https://www.capa.run/keji_content?id=31) |

**反向证据（诚实列出）**：Be My Eyes 的整屏单按钮被 AFB AccessWorld 评为「不能更简单」`[B]`
[afb.org/aw/16/2/15488](https://afb.org/aw/16/2/15488)。

### 9.3 语音优先在嘈杂环境与公共场合的问题

- **隐私顾虑有实证**：盲人用户认为语音助手回答常「过于冗长或过于有限」，且
  **在公共场合因隐私顾虑改变交互方式**（担心陌生人听到私事）
  `[C]` ["Siri Talks at You", Abdolrahmani, Kuber & Branham, ASSETS 2018](https://dl.acm.org/doi/10.1145/3234695.3236344)
  —— **这条直接命中「在地铁上大声说出自己的位置和『我是盲人』」的场景。**
- **嘈杂环境 WER**：见 §9.1 #6。
- **未找到**：r/Blind 关于「不愿在公共场合说话」的一手社区帖（`site:reddit.com` 过滤失效）；
  也未找到中文语境下的同类调研。

**对本项目的具体含义**：AidRun 的语音下单**必然发生在户外或准备出门时**，
且内容必然包含「我在哪」「我什么时候要跑」。这是比通用语音助手更敏感的组合。
**建议**：保留表单路径不只是降级出路，**它同时是隐私出路** ——
`spec.md:75` 的「表单从预约页内可达且不离开屏幕」这条要保住，并在首次使用时明确告知用户可以切换。

### 9.4 产品方那个「减法 + Magic Tap」假设可能错在哪里

1. **把「操作步数」当成成本函数，但盲人端真正的成本大头是确认与纠错。**
   —— **有证据**：80.3% 语音输入时间花在编辑 `[C]`；纯音频复核漏检约 50% `[C]`。
   减掉 5 个焦点省下的几次滑动，抵不上一次接错单造成的重下单成本。
2. **「占屏幕大半的主按钮」对全盲用户几乎无收益。** —— **有证据** `[A]`。
   它服务的是低视力和运动障碍用户。这一项应降级为「不反对，但不是 A 类的无障碍收益」。
3. **把 a11y 社区反对「独立无障碍版本」误读成了反对「可配置」。** —— **推断**（有 WebAIM / W3C 原文对照）。
   WebAIM 反对的是双维护、信息不对等的第二个站点；而盲人交通 App 研究里
   「可配置性」恰恰是用户最想要的特性之一 `[C]`。
4. **Magic Tap 被当成「熟练用户不退化」的护栏，但它是一个你不拥有、也无法保证用户知道的按键。**
   —— **有证据** `[A][D]`。且论证是循环的：**能想到用 Magic Tap 的人，本来也能应付 8 个焦点。**
5. **四个假设全部围绕「下单那一步」，但国内实地报道显示视障用户的主要痛点在下单之后。**
   —— **有证据** `[B]`：找不到车、不知道车到没到、不知道预估时间（滴滴三条用户原话，§3.2.3）。
   **把设计预算压在首页焦点数上，可能优化了一个不是瓶颈的环节。**

---

## 10. 未解决问题与需要用户测试才能定的事项

### 10.1 本次调研明确「未找到证据」的清单

| # | 问题 | 状态 |
|---|---|---|
| 1 | **Be My Eyes 首页真实 VoiceOver 焦点数** | 「5 tab + 2 按钮 = 7」是文字推算。**这是本报告 N 值推导的唯一锚点，却没有实测证据。** 必须真机 VoiceOver 逐个右滑数一遍 |
| 2 | **首页焦点数上限的任何标准依据** | 不存在。WCAG / GB/T 37668 / 工信部规范 / Apple HIG 均无此类条款 |
| 3 | **减少焦点数量是否真的减少时间** | 未找到任何把 VoiceOver 遍历时间对元素数量做回归的研究，也未找到「滑动成本很低所以减焦点收益被高估」的实测。**产品方与反方都缺证据** |
| 4 | **VoiceOver 用户的目标尺寸阈值** | 文献空白。没有任何研究给出针对屏幕阅读器用户的目标尺寸数字。**任何「盲人需要 X pt」的说法都是设计民俗** |
| 5 | **swipe-to-next 导航路径下尺寸是否主导** | 未找到直接实验证据 |
| 6 | **中文 ASR 确认词混淆率**（「对/不对」「是/不是」的混淆矩阵） | 未找到任何论文报告该数字。**建议自采黄金语料实测**，`scripts/validate-golden-corpus.mjs` 是现成落点 |
| 7 | **唤起→可说话的延迟容忍毫秒数** | Alexa / Google / Siri 均无官方数值。所有 300 ms / 500 ms 的说法都是 `[D]` |
| 8 | **读回长度的官方上限** | Google / Amazon / Apple 均无字数或秒数规定 |
| 9 | **盲人偏好「连续整句指令 vs 分步追问」的直接实证对比** | **未找到做过这一 A/B 的论文。这是本次调研最大的证据缺口**，说明该决策必须靠本项目自己的用户测试 |
| 10 | **视障用户在原生移动 App 长表单上的完成率/弃用率** | 现有数据全部是 Web 场景 |
| 11 | **Magic Tap 的采用率 / 知晓率统计** | 没有任何可核查调查给出「多少比例的 VoiceOver 用户知道 Magic Tap」。「大多数用户不知道」这个说法**无法证实也无法证伪** |
| 12 | **滴滴 / Lyft / Bolt 有进行中订单时的首页确切形态** | 无官方图文或商店截图可核查 |
| 13 | **中国大陆助盲/陪跑类服务的实名认证法定要求条文** | 未查证 —— **需法务确认，不能只按转化率决定 gate 时机** |
| 14 | **GB/T 37668-2019 条款 3.3.4.4「目标尺寸」的具体数值** | 取得完整目录与多条条款正文，该条（三级）数值未确认 |
| 15 | **APP 侧《互联网应用适老化及无障碍水平评测体系》指标明细表** | 网站侧已取得全文；APP 侧（信通院受理）仅二手描述，原文未获取 |
| 16 | **SIA《移动应用（App）无障碍通用设计规范》** | **未找到该名称的独立文件，无法证实其存在。建议从项目文档中撤下该引用** |
| 17 | **带时间戳的盲人读屏叫车实机演示视频** | 未找到任何一个。搜到的 B 站视频是概念设计与探店，非打车场景 |

### 10.2 必须真机 + 真人测试才能定的事项

| # | 事项 | 为什么必须实测 |
|---|---|---|
| 1 | **§4.2 每一处 `.combine` 合并后的朗读文本** | 合并不当会产出一长串糊在一起的读音，比拆开更糟。「减焦点」不等于「减混乱」`[C]` |
| 2 | **地图 `.accessibilityHidden(true)` 后是否有信息损失** | 位置摘要必须真的能替代地图。且 B 类用户不开读屏，实测需分别覆盖 A / B 两类 |
| 3 | **2000 ms 尾静音是否真的够用** | 中文长句停顿分布未见中文语料研究。建议先做 A/B：2000 ms vs 3000 ms，记录被截断率 |
| 4 | **收窄后的 8 条确认白名单是否够用** | 方言与长句表达会被判为「非确认」。这是可接受方向的失败，但要量化多说两轮的频率 |
| 5 | **提案 5.5：真人对着麦克风走一遍完整语音下单** | `tasks.md` 自己写了「自动化测试跑通不等于语音链路可用」。且生产 `AMAP_WEB_KEY` 未配，地点抽取线上验不了 |
| 6 | **「≤3 决策点 / ≤60 秒」判据本身** | 需实测计时。§1.2 的 31-40 s 是预算推算，不含用户思考时间 |
| 7 | **常用出发点是否真能消掉一个决策点** | 需先验证「盲人跑者 80% 从同一地点出发」这个假设。这是 §1.1 最高杠杆建议的前提，**目前是推断不是数据** |

### 10.3 需要向后端提的问题（走 `demo/docs/handoff.md`）

1. `missing: ADDRESS` 的歧义（提案 2A.8 已提，等回复）
2. 下单请求体是否已含**配速区间**与**训练距离**槽位（§3.2.1）—— 若无且要做，需契约变更
3. 是否支持**常用出发点**的存储与拉取（§1.1）—— 若无且要做，需契约变更

---

## 11. 参考文献

### `[A]` 一手规范 / 官方文档 / 平台 API

**W3C / WCAG**
- WCAG 2.2 SC 2.5.8 Target Size (Minimum) — https://www.w3.org/TR/WCAG22/#target-size-minimum
- WCAG 2.2 Understanding 2.5.8 — https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html
- WCAG 2.2 Understanding 2.5.5 (Enhanced, AAA) — https://www.w3.org/WAI/WCAG21/Understanding/target-size.html · https://www.w3.org/WAI/WCAG22/Understanding/target-size-enhanced.html
- SC 2.4.3 Focus Order — https://www.w3.org/TR/WCAG22/#focus-order
- SC 3.3.7 Redundant Entry — https://www.w3.org/TR/WCAG22/#redundant-entry
- SC 3.2.6 Consistent Help — https://www.w3.org/TR/WCAG22/#consistent-help
- SC 2.2.1 Timing Adjustable — https://www.w3.org/TR/WCAG22/#timing-adjustable
- SC 2.3.1 Three Flashes — https://www.w3.org/TR/WCAG22/#three-flashes-or-below-threshold
- SC 1.4.3 Contrast (Minimum) — https://www.w3.org/TR/WCAG22/#contrast-minimum
- SC 1.4.11 Non-text Contrast — https://www.w3.org/TR/WCAG22/#non-text-contrast
- SC 4.1.2 Name, Role, Value — https://www.w3.org/TR/WCAG22/#name-role-value
- Understanding SC 3.3.4 Error Prevention (Legal, Financial, Data) — https://w3c.github.io/wcag21/understanding/error-prevention-legal-financial-data.html
- WCAG 2.2 Conformance（conforming alternate version）— https://www.w3.org/WAI/WCAG22/Understanding/conformance
- WCAG 工作组 issue #1831 / #1894（索要 24×24 的实证依据）— https://github.com/w3c/wcag/issues/1831 · https://github.com/w3c/wcag/issues/1894

**Apple**
- HIG Accessibility — https://developer.apple.com/design/human-interface-guidelines/accessibility
- HIG Typography — https://developer.apple.com/design/human-interface-guidelines/typography
- HIG VoiceOver — https://developer.apple.com/design/human-interface-guidelines/voiceover
- HIG Siri — https://developer.apple.com/design/human-interface-guidelines/siri
- HIG Live Activities — https://developer.apple.com/design/human-interface-guidelines/live-activities/
- HIG Accessing private data — https://developer.apple.com/design/human-interface-guidelines/patterns/accessing-private-data/
- `accessibilityElement(children:)` — https://developer.apple.com/documentation/swiftui/view/accessibilityelement(children:)
- `AccessibilityActionKind`（含 `.magicTap`）— https://developer.apple.com/documentation/swiftui/accessibilityactionkind
- `accessibilityAction(_:_:)` — https://developer.apple.com/documentation/swiftui/view/accessibilityaction(_:_:)
- `accessibilityRotor(_:entries:entryLabel:)` — https://developer.apple.com/documentation/swiftui/view/accessibilityrotor(_:entries:entrylabel:)
- `AccessibilityNotification.Announcement` — https://developer.apple.com/documentation/accessibility/accessibilitynotification/announcement
- `@ScaledMetric` — https://developer.apple.com/documentation/swiftui/scaledmetric
- `accessibilityReduceMotion` — https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion
- `accessibilityPerformMagicTap()` — https://developer.apple.com/documentation/objectivec/nsobject-swift.class/accessibilityperformmagictap()
- Supporting Accessibility（响应链分发，归档）— https://developer.apple.com/library/archive/featuredarticles/ViewControllerPGforiPhoneOS/SupportingAccessibility.html
- `AppShortcutsProvider` — https://developer.apple.com/documentation/appintents/appshortcutsprovider
- Creating controls to perform actions across the system — https://developer.apple.com/documentation/widgetkit/creating-controls-to-perform-actions-across-the-system
- `ControlWidgetButton` — https://developer.apple.com/documentation/widgetkit/controlwidgetbutton
- Back Tap 使用说明 — https://support.apple.com/en-us/111772
- Shortcuts：轻点背面运行快捷指令 — https://support.apple.com/guide/shortcuts/run-shortcuts-tapping-iphone-apd897693606/ios
- WWDC25 Session 277（SpeechAnalyzer / SpeechDetector）— https://developer.apple.com/videos/play/wwdc2025/277/
- 设置医疗急救卡 — https://support.apple.com/en-us/105072

**语音平台**
- Azure Speech：how-to-recognize-speech（`Speech_SegmentationSilenceTimeoutMs` 等）— https://learn.microsoft.com/en-us/azure/ai-services/speech-service/how-to-recognize-speech
- Dialogflow CX Advanced speech settings — https://docs.cloud.google.com/dialogflow/cx/docs/concept/advanced-speech
- Dialogflow CX `BargeInConfig` — https://docs.cloud.google.com/ruby/docs/reference/google-cloud-dialogflow-cx-v3/latest/Google-Cloud-Dialogflow-CX-V3-BargeInConfig
- Google Conversation Design：Confirmations — https://developers.google.com/assistant/conversation-design/confirmations
- Google Conversation Design：Errors — https://developers.google.com/assistant/conversation-design/errors
- Alexa Dialog Interface Reference — https://developer.amazon.com/en-US/docs/alexa/custom-skills/dialog-interface-reference.html
- Alexa Manage Skill Session — https://developer.amazon.com/en-US/docs/alexa/custom-skills/manage-skill-session-and-session-attributes.html
- Invoking Alexa（attention system / Start & End of Request earcon / barge-in）— https://developer.amazon.com/en-GB/docs/alexa/alexa-auto/invoking-alexa.html
- MDN Using the Web Speech API — https://developer.mozilla.org/en-US/docs/Web/API/Web_Speech_API/Using_the_Web_Speech_API
- 阿里云 语音地址输入识别 — https://help.aliyun.com/zh/address-purification/addrpapi/developer-reference/voice-address-recognition

**中国大陆标准与法规**
- 《中华人民共和国无障碍环境建设法》全文（最高检）— https://www.spp.gov.cn/spp/fl/202306/t20230628_618991.shtml
- GB/T 37668-2019 正文 PDF — https://www.capa.run/static/image/img_media/_GB_T_37668-2019_信息技术_互联网内容无障碍可访问性_技术要求与测试方法_.pdf
- GB/T 37668-2019 复审/修订计划（std.samr）— https://std.samr.gov.cn/gb/search/gbDetailed?id=91890A0DA54C80C6E05397BE0A0A065D
- **YD/T 4211-2023 真实名称核查（域名服务隐私泄露风险防护指标要求）** — https://std.samr.gov.cn/hb/search/stdHBDetailed?id=FE86C10A0CF73123E05397BE0A0A2FC5
- 工信部《移动互联网应用（APP）适老化通用设计规范》全文（湖南省政府转载）— http://www.hunan.gov.cn/zqt/zcsd/202104/t20210416_16470434.html
- 工信部原文页 — https://www.miit.gov.cn/jgsj/xgj/wjfb/art/2021/art_81e8b738d6b24ad6a04f7ecb3f4e0702.html
- CAICT 官方解读（W3C 托管 PDF）— https://www.w3.org/2021/05/29-older-users-and-accessibility/slides/slides-dingliting.pdf
- 《互联网网站适老化及无障碍水平评测体系》修订版 PDF — http://wza.isc.org.cn/static/upload/202303/0310_180024_653.pdf
- 上海交通委《申程出行（一键叫车）使用问答》 — https://jtw.sh.gov.cn/zsk/20230323/2ed128b74fbb4241b9436a754cba56b6.html

**EN 301 549 / ISO / Google Android**
- EN 301 549 §11 等同采用 HTML 版（加拿大 CAN/ASC）— https://accessible.canada.ca/en-301-549-accessibility-requirements-ict-products-and-services-11-software
- ISO/TS 9241-411:2012 官方范围（用于撤销「9 mm 规定」的误传）— https://www.iso.org/standard/54106.html
- Google Accessibility：48×48 dp ≈ 9 mm — https://support.google.com/accessibility/android/answer/7101858
- Android 16 Progress-centric notifications (Live Updates) — https://developer.android.com/about/versions/16/features/progress-centric-notifications

**竞品官方**
- Be My Eyes：Getting Started — https://support.bemyeyes.com/hc/en-us/articles/360005528557-Getting-Started-with-Be-My-Eyes
- Be My Eyes：Call a sighted volunteer — https://support.bemyeyes.com/hc/en-us/articles/360005522738-Call-a-sighted-volunteer
- Be My Eyes：iOS Use Siri — https://support.bemyeyes.com/hc/en-us/articles/360007464677-iOS-Use-Siri-with-Be-My-Eyes
- Aira Explorer 官方 — https://aira.io/aira-explorer-app/ · https://aira.io/new-mobile-app/
- United In Stride 官网 — https://www.unitedinstride.com/ · https://www.unitedinstride.com/find-a-partner
- United In Stride → Achilles 迁移公告 — https://www.achillesinternational.org/blog/unitedinstride
- Microsoft Soundscape 停更说明 — https://www.microsoft.com/en-us/research/product/soundscape/support/
- Uber Help：Check the status of my order — https://help.uber.com/en/ubereats/restaurants/article/check-the-status-of-my-order-?nodeId=4148ea8b-c9d8-409d-b7bf-b2fcb019a498
- Uber Newsroom：App 改版 — https://www.uber.com/us/en/newsroom/were-redesigning-the-uber-app-just-for-you/
- Uber Rider Safety Features（Trusted Contacts）— https://www.uber.com/za/en/ride/safety/rider-safety-features
- Uber Assist — https://www.uber.com/au/en/drive/services/assist/ · https://www.uber.com/nl/en/blog/what-is-uber-assist/
- DoorDash Help：并发下单 — https://help.doordash.com/en-us/consumers/article/can-i-order-from-different-restaurants-at-the-same-time
- Grab 官方博客：Live Activities — https://www.grab.com/inside-grab/stories/live-activities-grab-lock-screen-ios-apple/
- Lyft Help：How to navigate a ride — https://help.lyft.com/hc/en-us/all/articles/115012926147
- Life360 Emergency Contacts — https://support.life360.com/hc/en-us/articles/23053433936151-Life360-Emergency-Contacts
- 争渡读屏官方文档 — https://www.zdsr.com/docs/zdsr/30/ · https://www.zdsr.com/docs/zdsr/6/

### `[B]` 竞品可核查实证

- blindios.uk：Be My Eyes 逐 tab 走查（视障者撰写）— https://www.blindios.uk/be-my-eyes
- AFB AccessWorld：Be My Eyes 评测（「不能更简单」）— https://afb.org/aw/16/2/15488
- AFB AccessWorld：Aira 入门 — https://www.afb.org/aw/18/9/15178
- AFB AccessWorld：Uber/Lyft 对视障出行的影响 — https://afb.org/aw/17/11/15386
- AFB：iOS 26 无障碍功能（Magic Tap 可关闭）— https://afb.org/blog/entry/ios-26-accessibility-features
- Henshaws：Seeing AI 2025 改版（3 tab）— https://www.henshaws.org.uk/hints-and-tips/seeing-ai-the-2025-update/
- App Store：Be My Eyes — https://apps.apple.com/us/app/be-my-eyes/id905177575
- Google Play：Be My Eyes — https://play.google.com/store/apps/details?id=com.bemyeyes.bemyeyes
- App Store：Aira Explorer — https://apps.apple.com/us/app/aira-explorer/id1590186766
- App Store 中国区：小艾帮帮 — https://apps.apple.com/cn/app/id1361445580
- App Store 中国区：申程出行 — https://apps.apple.com/cn/app/id1490243036
- App Store 中国区：高德地图 — https://apps.apple.com/cn/app/id461703208
- 应用宝：点明安卓 — https://sj.qq.com/appdetail/com.dianming.phoneapp
- 小米商店：保益悦听 — https://m.app.mi.com/detail/36668
- 新华社：高德视障导航上线 — http://www.news.cn/tech/20240819/005fbcd95df64564b42b0e8961ce2819/c.html
- 新华网：视障跑友与陪跑志愿者 — http://www.news.cn/20240820/70ddc2ea18a749699d48f6636eb7841e/c.html
- CBS：TV anchor 触发观众 Echo 下单 — https://www.cbsnews.com/news/tv-news-anchors-report-accidentally-sets-off-viewers-amazons-echo-dots
- CBS：Alexa 私人对话被发给联系人（Portland）— https://www.cbsnews.com/news/amazon-alexa-echo-device-recorded-conversation-sent-to-contact/
- BBC：Alexa 玩具屋误单 — https://feeds.bbci.co.uk/news/technology-38553643
- TechCrunch：DoorDash DoubleDash — https://techcrunch.com/2021/08/05/with-doubledash-doordash-users-can-tack-on-multiple-orders-without-additional-fees/
- WebAIM：对 ADA NPRM 的回应（45.4% 很少/从不用读屏专版）— https://webaim.org/blog/response-to-ada-nprm/
- 澎湃：50+ 适老化软件测评（全民 K 歌关怀模式）— https://www.thepaper.cn/newsDetail_forward_24096547
- 南都：视障出行独立（找不到车等痛点）— https://m.mp.oeeee.com/a/BAAFRD000020230913847239.html
- AppleVis 播客：Be My Eyes Virtual Volunteer 演示 — https://applevis.com/podcasts/introducing-be-my-eyes-virtual-volunteer-demonstration-some-game-changing-real-world-use
- Be My Eyes 官方 YouTube — https://www.youtube.com/c/bemyeyes
- United In Stride 陪跑教学（带音频描述）— https://www.youtube.com/watch?v=kOnKauvk2oI

### `[C]` 学术研究 / 行业报告 / 无障碍机构测评

**触达尺寸与触控精度**
- Parhi, Karlson & Bederson (2006), MobileHCI '06 — https://dl.acm.org/doi/10.1145/1152215.1152260
- Henze, Rukzio & Boll (2011), MobileHCI '11（1.2 亿次触摸）— https://nhenze.net/uploads/100000000-Taps-Analysis-and-Improvement-of-Touch-Performance-in-the-Large.pdf
- Leitão & Silva (2012), PLoP '12（N=40，65-95 岁）— https://mural.maynoothuniversity.ie/id/eprint/6045/1/PS-Target-Spacing.pdf
- Kobayashi et al. (2011), INTERACT 2011 — https://opendl.ifip-tc6.org/db/conf/interact/interact2011-1/KobayashiHMAHI11.pdf
- Kane, Wobbrock & Ladner (2011), CHI '11（盲人 vs 明眼人触摸偏差）— http://faculty.washington.edu/wobbrock/pubs/chi-11.05.pdf
- Bi, Li & Zhai (2013), CHI '13 FFitts Law — https://www3.cs.stonybrook.edu/~xiaojun/pdf/FFitts.pdf
- Joh et al. (2022), W4A '22 — https://doi.org/10.1145/3493612.3520454
- Smaradottir et al. (2018), Hindawi（视障用户手势难度，**全文未核到**）— https://www.hindawi.com/journals/misy/2018/6941631/

**盲人与语音助手 / 屏幕阅读器**
- Abdolrahmani, Kuber & Branham, ASSETS 2018 "Siri Talks at You"（公共场合隐私顾虑）— https://dl.acm.org/doi/10.1145/3234695.3236344
- Branham & Mukkath Roy, ASSETS 2019 "Reading Between the Guidelines" — https://doi.org/10.1145/3308561.3353797
- Abdolrahmani et al., TACCESS 2020 12(4):18 — https://dl.acm.org/doi/fullHtml/10.1145/3368426
- VERSE, ASSETS 2019（语音助手「便利但浅」）— https://dl.acm.org/doi/pdf/10.1145/3308561.3353773
- Pradhan, Mehta & Findlater, CHI 2018 "Accessibility Came by Accident" — https://dl.acm.org/doi/10.1145/3173574.3174033
- Azenkot & Lee, ASSETS 2013（80.3% 时间在编辑）— https://dl.acm.org/doi/10.1145/2513383.2513440
- Lee et al., TACCESS 2020（纯音频复核漏检约 50%）— https://dl.acm.org/doi/fullHtml/10.1145/3382039
- Open Challenges of Blind People using Smartphones — https://arxiv.org/pdf/1909.09078
- 盲人挫折日记研究（N=100）— https://www.researchgate.net/publication/220302591
- 盲人交通 App 焦点小组（可配置性为最想要特性）— https://par.nsf.gov//servlets/purl/10063454
- COVID 数据可视化无障碍审计 — https://dl.acm.org/doi/10.1145/3557899
- 屏读用户求职表单研究（55.6% 成功率）— https://pmc.ncbi.nlm.nih.gov/articles/PMC10961918/
- A11y-CUA（屏读用户 2.28× 耗时）— https://arxiv.org/pdf/2602.09310
- Click-Away Pound 2019（69% 因难用离开）— https://www.clickawaypound.com/
- WebAIM Screen Reader User Survey #10 — https://webaim.org/projects/screenreadersurvey10/

**语音识别与 VUI**
- CHI 2023 Trust after VA Failures（199 例失败、overcapture）— https://dl.acm.org/doi/fullHtml/10.1145/3544548.3581152 · https://arxiv.org/pdf/2303.00164
- AGIF 多意图（MixATIS overall acc 60.2）— https://arxiv.org/pdf/2004.10087
- Speech2Slot（错误集中在实体槽位）— https://arxiv.org/abs/2105.04719
- ASR 噪声鲁棒性（每 −5 dB 错误率翻倍）— https://link.springer.com/article/10.1186/s13636-026-00458-1
- ASR-EC 中文纠错基准 — https://arxiv.org/html/2412.03075v1
- Older Adults' VA Errors（转写错误仅 6.3%）— https://arxiv.org/pdf/2403.02421
- Amazon Science：Significant ASR Error Detection — https://www.amazon.science/publications/significant-asr-error-detection-for-conversational-voice-assistants
- VUI discoverability — https://www.researchgate.net/publication/307090834
- 语音停顿分布综述（三模态 150/500/1500 ms）— https://www.mdpi.com/2226-471X/8/1/23
- Stivers et al., PNAS 2009（换手间隙模态 200 ms）— https://www.pnas.org/doi/10.1073/pnas.0903616106
- Snopes：Alexa 玩具屋事件复核 — https://www.snopes.com/fact-check/alexa-orders-dollhouse-and-cookies/

**设计研究机构**
- NN/g Response Times（0.1 / 1 / 10 秒）— https://www.nngroup.com/articles/response-times-3-important-limits/
- NN/g Modes in User Interfaces — https://www.nngroup.com/articles/modes/
- NN/g Permission Requests — https://www.nngroup.com/articles/permission-requests/
- NN/g Progressive Disclosure — https://www.nngroup.com/articles/progressive-disclosure/
- Baymard：Delayed Account Creation — https://baymard.com/blog/delayed-account-creation
- Orange 无障碍指南：iOS VoiceOver — https://a11y-guidelines.orange.com/en/mobile/ios/voiceover/

**中国机构测评**
- 信息无障碍研究会「可及评测」43 款 App（滴滴 iOS 4.0 / Android 3.5）— https://www.capa.run/keji_content?id=31
- 中国信通院《信息无障碍白皮书》(2022-05) — http://www.caict.ac.cn/english/research/whitepapers/202208/P020220819516229188334.pdf
- 信息无障碍研究会 iOS 无障碍指南 — https://informationaccessibilityassociation.github.io/iosguideline/Understanding_Accessibility_on_iOS.htm

### `[D]` 二手来源（仅作佐证，不单独支撑任何硬性建议）

- AppleVis 论坛：阻止 Magic Tap 启动音乐 — https://www.applevis.com/forum/ios-ipados/there-way-prevent-magic-tap-launching-music-playback-when-not-music-app
- AppleVis 播客：Taming the Magic Tap — https://www.applevis.com/podcasts/taming-magic-tap-stop-accidental-media-playback-ios
- AppleVis bug：两指双击接电话时 VoiceOver 无响应 — https://www.applevis.com/bugs/ios/voiceover-can-times-become-unresponsive-when-using-two-finger-double-tap-gesture-answer
- AppleVis：Aira Explorer 条目 — https://www.applevis.com/apps/ios/lifestyle/aira-explorer
- AppleVis：Soundscape 开源公告 — https://www.applevis.com/blog/microsoft-discontinue-its-soundscape-app-make-code-available-open-source-software
- Create with Swift：Preparing Your App for VoiceOver MagicTap — https://www.createwithswift.com/preparing-your-app-for-voiceover-magictap/
- CVS Health SwiftUI a11y techniques：MagicTap — https://github.com/cvs-health/ios-swiftui-accessibility-techniques/blob/main/iOSswiftUIa11yTechniques/Documentation/MagicTap.md
- Apple Developer Forums 82839 / 679230（SFSpeechRecognizer 无 end-silence 属性）— https://developer.apple.com/forums/thread/82839 · https://developer.apple.com/forums/thread/679230
- Neil Squire：Be My Eyes 2018 版评测（布局已过时）— https://www.neilsquire.ca/eyes-app-review/
- 网易：滴滴盲人无障碍出行全国上线 — https://m.163.com/dy/article/IAGMU1CA0519C6T9.html
- 北京日报：滴滴盲人服务 — https://xinwen.bjd.com.cn/content/s64d2e075e4b0285efd6d8d84.html
- 澎湃：滴滴老年人小程序一键叫车 — https://m.thepaper.cn/baijiahao_10898413
- FinClip：滴滴关怀版 — https://www.finclip.com/news/f/67009.html
- 网易科技：高德助老打车 — https://www.163.com/tech/article/GJHUJ7RB00097U7R.html
- 北京日报：老年人打车难试试这些招（美团助老语音播报）— https://news.bjd.com.cn/2023/11/27/10631357.shtml
- 人民网：嘀嗒助老出行小程序 — http://bj.people.com.cn/n2/2021/0325/c82840-34639797.html
- 新京报：嘀嗒助老小程序 70 城 — https://www.bjnews.com.cn/detail/1744891878168702.html
- 中新网：一键叫车让老年人智慧出行 — https://www.chinanews.com.cn/life/2022/01-26/9662033.shtml
- 新浪财经：宜兴阳羡行三种叫车模式（语音消息转发不做 ASR）— http://cj.sina.com.cn/articles/view/2474295231/937abfbf00101m622
- 澎湃：一键叫车智慧屏遇冷 — https://m.thepaper.cn/detail/28454053
- 新榜：支付宝长辈模式（首页仅两卡片）— https://www.newrank.cn/article/detail/17613
- 中国日报：微信关怀模式 — https://cn.chinadaily.com.cn/a/202109/27/WS6151640ca3107be4979f0016.html
- 周到：小艾帮帮报道 — http://static.zhoudaosh.com/files/cnews/2021/20211020/4F9B05807313CCAE9902D193BCE2BD3C0A0762167A77C63670F9A689DF80ACB0/3.html
- 知乎：盲人如何使用触屏手机（国内读屏软件现状）— https://zhuanlan.zhihu.com/p/373078490
- 知乎 / CSDN：高德「你好小德」实测 — https://zhuanlan.zhihu.com/p/61205930 · https://blog.csdn.net/xiongmosy/article/details/89495025
- 新浪财经：黑暗跑团 — https://finance.sina.com.cn/jjxw/2024-11-30/doc-incxvawv1188534.shtml
- C114：工信部适老化改造数据 — https://m.c114.com.cn/w16-1241193.html
- 人人都是产品经理：美团外卖产品分析（约 2018）— https://www.woshipm.com/evaluating/1629802.html
- Sardine：KYC Conversion Rates（厂商博客）— https://www.sardine.ai/blog/kyc-conversion-rates
- Incognia：定位权限授权率（厂商博客）— https://www.incognia.com/blog/how-to-achieve-high-opt-in-rate-when-requesting-user-location-permissions
- Adrian Roselli：24×24 像素书签工具 — https://adrianroselli.com/2022/05/24x24-pixel-cursor-bookmarklet.html
- Sarah Brisendine：Designing VoiceOver Experiences（Uber 从业者随笔）— https://sbrisendine.com/designing-voiceover-experiences/
- TechHive：Google Home 收音提示音 — https://www.techhive.com/article/578371/google-home-nest-speakers-audio-cue-when-assistant-is-listening.html
- WWeek：Portland 事件原始报道 — https://www.wweek.com/news/2018/05/26/portland-family-says-their-amazon-alexa-recorded-private-conversations-and-sent-them-to-a-random-contact-in-seattle/
- Surrey County Council：Getting Started with Aira Explorer PDF — https://www.surreycc.gov.uk/__data/assets/pdf_file/0018/446031/Getting-Started-with-Aira-Explorer-v1-30052025_112717.pdf
- B 站：盲人怎么用手机 — https://www.bilibili.com/video/BV1gf4y197fk/
- B 站：苹果无障碍线下探店 — https://www.bilibili.com/video/BV1VCyDYQEnc/

### 抓取失败记录（引用前建议人工复核）

AppleVis 全站、Be My Eyes 帮助中心、ACM DL / Wiley 全文、ETSI 原始 PDF、Perkins、Envision 帮助中心
在本次抓取中返回 **403/402**；App Store 页面被重定向至中国区首页。
标注这些域名的内容来自搜索引擎索引的页面正文摘录，**而非直接读取页面**。

---

## 附录 A：URL 核验记录（已执行，2026-08-05）

```bash
grep -oE 'https?://[^)"< ]+' <报告> | sed 's/[.,;]*$//' | sort -u \
| xargs -P 12 -I{} sh -c 'c=$(curl -sIL -o /dev/null -w "%{http_code}" --max-time 12 \
    -A "Mozilla/5.0 ... Chrome/120.0 Safari/537.36" "{}"); [ "$c" = "200" ] || echo "$c {}"'
```

**结果：190 条唯一 URL，非 200 输出为空。**

核验器本身已用探针验证可用（`https://example.com/<不存在的路径>` → `BAD 404`；不存在的域名 → `BAD 000`；
真实 W3C 条款 URL → 通过）。子调研线报告的 AppleVis / ACM DL / ETSI 403 是抓取工具被反爬拦截，
换浏览器 User-Agent 后均返回 200。

**已知残余风险**：`curl -L` 跟随重定向后报最终状态，因此「重定向到首页」也会计为 200
（App Store 中国区重定向是典型）。已用 WebFetch 对两条最吃重的断言做一手复核：

| 断言 | 复核结果 |
|---|---|
| **YD/T 4211-2023 不是无障碍标准** | ✅ 一手确认。std.samr 详情页：编号 `YD/T 4211-2023`，名称**《域名服务隐私泄露风险防护指标要求》**，2023-05-22 发布 / 2023-08-01 实施，**推荐性** |
| **Magic Tap 沿响应链分发、无实现时落到系统默认动作** | ✅ 一手确认。Apple 归档文档原文："It searches for the method using the responder chain, **starting with the element that has the VoiceOver focus**. If no object implements the appropriate method, UIKit performs the **default system action** for that gesture." 以及 "To handle Magic Tap gestures from anywhere in your app, implement the `accessibilityPerformMagicTap` method in your app delegate." |

**未逐条复核**：其余 188 条只做了 HTTP 200 检查，未验证页面内容与引用一一对应。
报告中已标「全文未核到」「二手转述」的条目（Smaradottir 2018、PwC 46%、Signicat 68%、Incognia +12%、
Jin et al. 2007）**不得单独支撑任何决策**。

## 附录 B：本报告建议与现有自动检查的交互

| 建议 | 与现有测试的关系 |
|---|---|
| 地图 `.accessibilityHidden(true)` | **副作用是好的**：`AccessibilityAuditTests.swift:114` 的唯一白名单项（`blindRunnerHomeAuxiliaryMap` / `blindBookingAuxiliaryMap`）**可以随之删除** —— 隐藏后审计根本遍历不到它。白名单归零是净收益 |
| 保留「重复当前状态」 | `testBlindRunnerHomeOffersRepeatCurrentStatus`（`:84-98`）已锁死。**任何「改为 Magic Tap / 摇一摇触发」的方案都会挂这条测试** |
| 64 pt 改 `@ScaledMetric` | `testBlindRunnerPrimaryButtonMeetsMinimumTouchTarget`（`:68-78`）断言 `>= 64`，`@ScaledMetric` 只会让它变大，**不会挂** |
| 「重试加载」补 64 pt | 现有测试**不覆盖**该按钮（只测 `blindRunnerHomeStartBookingButton`）。改动时需同时加断言 |
| 焦点总数上限 / 遍历顺序 | **现有审计查不到这两项**（`performAccessibilityAudit` 是静态检查）。需新写断言 —— 这是新变更必须交付的一部分 |
| 确认词白名单收窄到 8 条 | 需改 `testOnlyExplicitAffirmativesAreTreatedAsConfirmation`（19 → 8）；`testNegationsContainingAffirmativeWordsAreNotConfirmation`（13 条否定）**不受影响，可保留** |

## 附录 C：落盘与后续动作

1. 本文件原样落到 `docs/research/blind-voice-booking-ia-20260805.md`
2. **修 spec 漂移**：`openspec/changes/enable-one-utterance-booking/specs/blind-runner-voice-first-experience/spec.md:13-17`
   的「Start place is NOT extracted from the full utterance」与实现相反，须改写为「地点从整句抽，单独修改时走 `resolve-address`」
3. **从项目文档撤下两处失效引用**：`YD/T 4211-2023`、SIA《移动应用（App）无障碍通用设计规范》
4. 向后端 `demo/docs/handoff.md` 提三个问题（见 §10.3）
5. 新开 OpenSpec 变更 `refocus-blind-runner-home`（范围见 §8 末）
