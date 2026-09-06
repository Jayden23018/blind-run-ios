# 有没有适配本项目的 Claude Code skill / 使用方式？（2026-09-02）

**问题**：市面上（官方 + GitHub + 个人实践）有没有值得给本仓库配的 skill / 插件 / 工作方式，
尤其针对**前端界面美观设计**与**盲人适配**两块。

**一句话结论**：**a11y 和 design-review 这两类最热门的现成方案，对本仓库的适用度是零** ——
它们无一例外建立在浏览器上（axe-core / jsx-a11y / Playwright MCP），而本仓库是原生 iOS 且
模拟器通道永久不可用。真正对得上的只有 iOS 通用 skill 一类，且只值得装**一个**。
**本轮最有价值的产出不是"该装什么"，而是核实过程中发现的两个自家缺口**：
① `.textClipped` 审计从未启用，而代码注释宣称它在抓横屏裁切；
② 真机 UI 测试拍的 9 张截图从未被导出，视觉反馈闭环断在最后一步。

---

## 1. 核实口径

- 联网：WebSearch / WebFetch，HN 真实评论走 HN Algolia API（免 key 返回原始评论）。
- 版本敏感 API **不信搜索转述**，一律读本机 SDK 头文件（上一次 `prefersAssistiveTechnologySettings`
  就是被 WebSearch 转述成错版本，见 `tts-rate-follows-voiceover-20260814.md`）。
- 本机环境：Xcode **26.2**（Build 17C52）。两台真机本轮均为 `unavailable`（未插线），
  **所以本报告没有任何真机运行结果**，涉及"跑起来会怎样"的部分一律标注为推断。

---

## 2. 现成方案分三类，只有一类能用

### 2.1 ⛔ a11y 审计类 skill —— 全是 Web，零适用

| 项目 | 实现 | 为什么用不了 |
|---|---|---|
| [masuP9/a11y-specialist-skills](https://github.com/masuP9/a11y-specialist-skills/) | WCAG 2.2 + WAI-ARIA APG，检查走 `@a11y-skills/audit` npm 包 + Playwright | 需要一个 DOM |
| [airowe/claude-a11y-skill](https://github.com/airowe/claude-a11y-skill) | axe-core（runtime）+ eslint-plugin-jsx-a11y（static） | React/Next 专用 |
| [alirezarezvani/a11y-audit](https://alirezarezvani.github.io/claude-skills/skills/engineering-team/a11y-audit/) | Scan → Fix → Verify，按框架生成修复代码（React/Vue/Angular/Svelte/HTML） | 框架列表里没有 SwiftUI |
| jeremylongshore/accessibility-test-scanner | ARIA 属性校验、键盘导航 | ARIA 在 iOS 上不存在 |

它们检查的对象（ARIA role、tab order、focus trap、`alt` 属性）在 iOS 上**没有对应物** ——
iOS 的等价概念是 `accessibilityTraits` / VoiceOver 遍历顺序 / `accessibilityLabel`，
两套模型不通约。装上去唯一的效果是让 Claude 用 Web 词汇讨论 SwiftUI 代码。

> 附带发现：这也解释了为什么本仓库的无障碍工作一直"没有现成轮子可用"——
> **不是没搜到，是这个生态位在 iOS 上基本空着**。

### 2.2 ⛔ design-review / 视觉设计类 —— 同样卡在浏览器

- **[OneRedOak/claude-code-workflows](https://github.com/OneRedOak/claude-code-workflows/tree/main/design-review)**
  是这一类里最出名的（design-review subagent + `/design-review` slash command + CLAUDE.md 设计原则）。
  它的核心价值主张是"**别让用户贴截图，让 agent 自己打开界面看**"，
  实现完全依赖 **Playwright MCP**。方法论可迁移，实现不可迁移。
- **[rohitg00/awesome-claude-design](https://github.com/rohitg00/awesome-claude-design)**（DESIGN.md 做法）：
  逐条核实后确认 **repo 内对原生 iOS/Android 的指导为零**，模板与导出格式全是 HTML/PPTX/PDF。
  该 repo 收录的社区批评值得原样记下，因为它对我们同样成立：
  - "fingerprinting" —— AI 出的界面千篇一律（同一种 teal 强调色、会闪的状态点、三列网格、
    每张卡片左侧一条竖线），一眼能认出是 AI 画的；
  - Malewicz 的判断是它与"中级设计师"之间的差距仍然显著，替代的是**出图**不是**策略**；
  - 反制手段是**在 prompt 里逐条点名拒绝**这些默认指纹，而不是泛泛地说"好看一点"。

### 2.3 ✅ iOS 通用 skill —— 有真东西，但只值得装一个

| 项目 | 规模 | 判断 |
|---|---|---|
| **[twostraws/SwiftUI-Agent-Skill](https://github.com/twostraws/swiftui-agent-skill)**（Paul Hudson） | 单个 `swiftui-pro` skill，MIT | **推荐**。README 明说刻意写短以省 token；覆盖面里**显式包含 VoiceOver**，且切入点是"LLM 实际会犯的错"（原文举的例子就是"AI 有时会把按钮做成 VoiceOver 看不见的"）——正好是本仓库的事故类型 |
| [avdlee/swiftui-agent-skill](https://github.com/vabole/apple-skills)（Antoine van der Lee） | 单 skill | 偏 `@Observable` / 视图失效 / Instruments 性能；本仓库瓶颈不在这 |
| **[CharlesWiltgen/Axiom](https://github.com/CharlesWiltgen/Axiom)** | **273 skills + 42 agents**，MIT | **不装**。理由见下 |

**Axiom 为什么否掉**（它是这个领域最完整的项目，值得写清楚）：

1. 它自带的 `xcui` 工具原文是 "drives and validates **simulator** UI & accessibility" ——
   本仓库模拟器通道因高德无 arm64-sim slice **永久不可用**，这恰好是它最对口的那个工具。
   `xclog`（捕获**模拟器**控制台）同理。
2. 它要求 Xcode 26+（本机 26.2 ✓）**与 iOS 26+ SDK**，主打 Liquid Glass 等 iOS 26 API；
   本仓库部署目标 **iOS 16**，这批建议一条都用不上，还会持续引诱往新 API 上写。
3. 273 个 skill 进上下文的成本与本仓库既有的 5 个 `aidrun-*` skill + 大量 hook 直接冲突。

> 不是说 Axiom 不好，是它假设的开发形态（模拟器 + 最新 SDK）与本仓库的物理约束正相反。
> 如果哪天模拟器通道恢复（高德出 arm64-sim slice），这条结论要重新判。

---

## 3. 本仓库已有的东西，比上面所有 a11y skill 都强

核实中发现 `blindRunUITests/AccessibilityAuditTests.swift`（**859 行**）已经在用
iOS 原生的 `performAccessibilityAudit`，且是真机跑。**本机 SDK 头文件实证**
（`Xcode.app/.../XCUIAutomation.framework/Headers/XCUIApplication.h:149`）：

```objc
- (BOOL)performAccessibilityAuditWithAuditTypes:(XCUIAccessibilityAuditType)auditTypes
    issueHandler:(nullable XCUI_NOESCAPE BOOL (^)(XCUIAccessibilityAuditIssue *issue))block
    error:(NSError **)outError
    API_AVAILABLE(macos(14.0), ios(17.0), tvos(17.0), watchos(10.0)) NS_REFINED_FOR_SWIFT;
```

iOS 侧可用的 7 个审计类型（`XCUIAccessibilityAuditTypes.h`，位掩码可按位或）：

| 类型 | 抓什么 |
|---|---|
| `.contrast` | 对比度不足 |
| `.elementDetection` | 元素识别不出来 |
| `.hitRegion` | 触达区域过小 |
| `.sufficientElementDescription` | 描述不充分（缺 label） |
| `.dynamicType` | 不支持动态字号 |
| `.textClipped` | **文本被截断** |
| `.trait` | traits 用错（例如按钮没有 `.button`） |

这套东西在**能力上直接盖过** §2.1 那些 Web skill：对比度、Dynamic Type、触达区域这三项，
axe-core 那边要么做不到、要么只能对 CSS 做静态推断。本仓库这份还额外做对了三件事，
比多数公开示例讲究：白名单每条写明理由、失败时打印元素 id/label/frame（因为审计本身只报
"Contrast failed" 不说是谁）、低版本设备明确 `XCTSkip` 而不是静默通过。

**所以"给盲人适配找个 skill"这个方向本身就问错了** —— 该找的不是 skill，是缺口。

---

## 4. 缺口 A：`.textClipped` 从未启用，而注释说它在抓横屏裁切 🔴

全仓 `performAccessibilityAudit` 调用点只有 **1 处**
（`blindRunUITests/AccessibilityAuditTests.swift:683`），审计类型集合是：

```swift
for: [.contrast, .dynamicType, .elementDetection, .hitRegion, .sufficientElementDescription]
```

**`.textClipped` 与 `.trait` 都不在里面。** 而同文件 `:560-566` 的注释逐字写着：

> 横屏审计。**这是本仓库唯一能验「横屏裁切」的通道** ……
> 审计里真正抓这件事的是 `.textClipped` 与 `.hitRegion`：矮窗口下被装饰地图挤扁的文本、
> 被底部常驻条盖住的按钮，都从这两条出来。

三条横屏用例（`:568` / `:583` / `:599`）调的正是同一个 `audit(_:)` helper ⇒
**"横屏裁切"这条从来没有被检查过**，`.textClipped` 在整个仓库里一次都没被启用过。
三条用例长期报绿，绿的是另外五项。

这与记忆 `low-vision-visual-channel-unaudited` 里 2026-08-22 真机 AX5 实测的
"志愿者端指标格截断成『…』未修"是**同一个缺陷面**：有一个能自动抓它的开关，
注释以为开着，实际没开。

**修法是一行**（把两个类型加进 `:684` 的集合）。但**这是发现缺陷不是顺手修好**：
按上述实测，加上去大概率立刻变红，而红的是真问题。本轮设备未连接，**没有跑过**，
以上是推断。

`.trait` 同样值得加 —— 按钮缺 `.button` trait 时 VoiceOver 不念"按钮"，
用户不知道那是个可点的东西，这对盲人端是硬伤。

> 这条正好是记忆 `claimed-fallback-may-not-exist-in-release` 的同型：
> **注释声称的检查，可能根本没接上。** 判据是"这个开关真的在参数列表里吗"，
> 不是"注释说它在"。

---

## 5. 缺口 B：截图拍了，但从来没人（包括 Claude）看过 🟡

这是"界面美观设计"那半个问题的答案所在。

官方 best practices 讲的视觉迭代循环是：**给视觉目标 → 实现 → 截图 → 自己比对 → 迭代**，
关键在于"给 Claude 一个它自己能跑的 check"，否则"看起来做完了"是唯一信号、
而人变成验证循环本身。本仓库 `AGENTS.md` §1 早就把这条做得更硬（落到 hook 上）——
**但视觉这条链是断的**：

- UI 测试里已有 **9 处** `attachScreenshot(...)`（`blindRunUITests.swift:501/511/514/552/1019/1041/1051/1648` 等），
  真机跑完，PNG 就在 result bundle 里；
- `scripts/device-test.sh:132` 只从 bundle 里取 `test-results summary`（通过/失败计数），
  **没有导出任何附件**；
- 于是那些截图只有人在 Xcode 里手动打开 result bundle 才看得到，Claude 一次都没看过。

补法不需要新工具，本机 `xcresulttool` 自带（已核实子命令存在）：

```bash
xcrun xcresulttool export attachments --path <result.xcresult> --output-path /tmp/shots
```

导出成 PNG 后 Claude 可以直接 `Read` 图片文件 —— 这就把 OneRedOak 那套
"让 agent 自己看界面"的方法论迁到了 iOS 上，**且走的是真机，比模拟器截图更可信**。

⚠️ 三条已知限制，别高估这条链：
1. **UI 测试构建永远没有高德 key**，地图一律降级成占位图（记忆
   `ui-test-defaults-verify-the-degraded-path`）⇒ 截图里的地图区域不是生产形态；
2. 截图能验布局、间距、截断、层级压盖，**验不了"好不好看"** —— 后者没有自动判据；
3. 记忆 `ui-test-launch-arg-typo-passes-silently`：靠 launch argument 改状态再截图的验证，
   开关没生效时两张图会逐像素相同而用例照样绿。断言要打在状态本身上。

---

## 6. 不该做的（被否掉的方案，留档比选中的更值钱）

| 方案 | 否掉的理由 |
|---|---|
| 装 Web a11y skill（axe-core / jsx-a11y 系） | 检查对象在 iOS 上不存在，§2.1 |
| 装 OneRedOak design-review | 依赖 Playwright MCP，需要 DOM |
| 装 Axiom（273 skills） | 主力工具驱动模拟器（本仓库永久不可用）+ 要求 iOS 26 API（部署目标 16），§2.3 |
| 用 Claude Design / DESIGN.md 那套做 iOS 界面 | 该 repo 对原生 mobile 的指导为零，导出格式是 HTML/PPTX/PDF |
| 为"美观"引入模拟器截图循环 | 高德无 arm64-sim slice，模拟器通道不存在；真机截图链路已具备（§5） |
| 再写一个 `aidrun-*` skill 装无障碍规则 | 已有 `aidrun-a11y-voice`；缺的是**检查**不是**文档**，按 AGENTS.md §1 该落到测试而不是第二份文档 |

---

## 7. 值得抄的两条外部实践（不引入依赖）

1. **拒绝 AI 视觉指纹要逐条点名**（来自 awesome-claude-design 的社区批评）：
   写"好看一点"没用，写"不要会闪的状态点 / 不要三列网格 / 不要每张卡左边一条竖线 /
   图标用 X 家不要默认 Lucide"才有效。对本仓库的意义在于：盲人端首屏的视觉规格
   已经由 `blind-ui-visual-benchmark-20260808.md` 定死（全宽圆角矩形、主按钮占内容区约 75%），
   那份基线本身就是最好的"反指纹"约束，改 UI 时**把它贴进 prompt**比让模型自由发挥强。
2. **iOS 视觉验证是公认弱项，不是本仓库特有的**。HN 上（2026-01-07，讨论串
   "Opus 4.5 is not the normal AI agent experience"）有开发者原话说他做 iOS app 时
   最大的问题就是 Claude Code 改不了 Xcode 设置、也没法在模拟器里验证设计元素。
   ⇒ 期望值放对：**这条链在 iOS 上就是要自己搭**，没有开箱即用的东西可装。

---

## 8. 建议的动作（按性价比排序）

| # | 动作 | 成本 | 收益 |
|---|---|---|---|
| 1 | `.textClipped` + `.trait` 加进 `AccessibilityAuditTests.swift:684` 的集合，真机跑一次看红成什么样 | 一行 + 一次真机 | 补上"横屏裁切"这个一直以为有、实际没有的检查 |
| 2 | `device-test.sh` 跑完导出截图附件到固定目录 | 一条命令 | 视觉反馈闭环接上，Claude 能自己看界面 |
| 3 | 装 `swiftui-pro`（twostraws） | 一条命令，MIT，刻意做小 | 覆盖 LLM 在 SwiftUI 上的典型错误，含 VoiceOver |
| 4 | 改 UI 时把 `blind-ui-visual-benchmark-20260808.md` 的规格贴进 prompt | 0 | 比任何"美观"prompt 都有效 |

第 1、2 条属于本仓库自己的缺口，与装不装 skill 无关，**优先级高于第 3 条**。

---

## 附：本轮的过程教训

差点又犯一次记忆 `synonym-mismatch-fakes-a-missing-feature` 记的那个错 ——
搜索结论一路指向"该给这个项目引入 iOS 无障碍自动审计"，
而 `AccessibilityAuditTests.swift` 已经在那儿躺了 859 行。
**触发点是搜索结果与仓库现状没对过账**：联网调研在回答"外面有什么"的时候，
很容易默认"我们没有"。落笔前扫一次仓库，成本一次 grep。
