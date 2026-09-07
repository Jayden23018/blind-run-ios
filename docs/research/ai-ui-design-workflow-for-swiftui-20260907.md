# AI 辅助的 SwiftUI 界面设计：该装什么、该怎么做（2026-09-07）

**问题**：Claude Code 里有没有好用的界面设计 skill / 工作流？本仓库的 UI「设计得没想象中好」该怎么系统性改善？开发流程应该是什么？

**一句话结论**：**别再找 skill 了，缺的不是工具**。生态里唯一值得读的一手材料是 Anthropic 官方
`frontend-design` 的 SKILL.md（71 行，**框架无关的部分占 96%**，只有 3 句是 Web 专属），它的核心不是
「审美清单」而是**两遍工作法**：先出 token 计划 → 对着 brief 自审是否落入默认值 → 才写代码 → 截图自评。
本仓库缺的正是这个流程的三个入口：**没有审美方向声明**（`ui-handoff-ios.md` 67.5K 全在讲「这页要有什么」，
没有一句讲「它该长什么样」）、**间距/圆角/动效没有 token**（颜色和字体有且做得很好，但 37 个视图文件里
1169 处视觉常量绝大多数是硬编码的 padding/cornerRadius）、**截图闭环最后一步没接**（昨天刚落地导出代码，
本机零 `.xcresult`，从没验证过；且 10 处截图全在功能用例里，横屏/无障碍用例一张图不拍）。
⚠️ 本轮同时**推翻了 `claude-code-setup-for-ios-a11y-20260902.md` 的一条结论** ——
「原生 iOS 的 skill 生态位基本空着」已不成立，现在有 3 个真实可用的（详见 §2.3）。

---

## 1. 核实口径

- 联网：WebSearch / WebFetch + 三条并行调研线；HN 真实评价走 HN Algolia API（免 key 返回原始评论）。
- **一手文件自己抓，不经转述**：官方 `frontend-design/SKILL.md`、`ui-ux-pro-max` 的 `swiftui.csv` 与
  `pro-rules.md`、`rshankras` 的 `ios/ui-review/SKILL.md` 均为 `curl` 原文；仓库硬指标走 `gh api`。
- **本机实测**：Xcode **26.2**（Build 17C52），`xcresulttool version 24514`，
  `xcrun mcpbridge` **不存在**（`unable to find utility`）。
- ⚠️ **本轮没跑过任何真机测试**，涉及「跑起来会怎样」的一律标注为推断。
- ⚠️ 子调研线返回的 HN 链接有 3 处是占位符 URL（`item?id=44xxxxx` 一类），**已全部替换为自己检索到的真实
  item id**；这正是 `tech-decision-research` 警告的「有 URL ≠ URL 是真的」。

---

## 2. 外面有什么：三类，只有一类真能用

### 2.1 ✅ Anthropic 官方 `frontend-design` —— 唯一值得整篇读的东西

[SKILL.md 原文](https://github.com/anthropics/claude-code/blob/main/plugins/frontend-design/skills/frontend-design/SKILL.md)（71 行，作者 Prithvi Rajasekaran / Alexander Bricken @anthropic.com）[高]

**逐行核对结论：只有 3 句是 Web 专属**，其余全部可用于 SwiftUI：

| 行 | 原文 | 判定 |
|---|---|---|
| L17 | `For web designs, the hero is the first thing viewers will see.` | Web 专属，跳过 |
| L55 | `be careful of structuring your CSS selector specificities` | Web 专属，跳过 |
| L59 | `visible keyboard focus`（在 quality floor 那句里） | iOS 无对应物（VoiceOver 焦点是另一回事） |

**可直接用的部分**（这才是价值所在）：

1. **两遍工作法**（L47-53，这是回答「开发流程是什么」的核心）：
   > "Work in two passes. First, brainstorm a short design plan… create a compact token system with color,
   > type, layout, and principles… Then review that plan against the brief before building: **if any part of it
   > reads like the generic default you would produce for any similar page** (work through a similar prompt to
   > see if you arrive somewhere similar) rather than a choice made for this specific brief — revise that part,
   > **say what you changed and why**. Only after you've confirmed the relative uniqueness of your design plan
   > should you start to write the code."

2. **截图自评**（L59）：
   > "Critique your own work as you build, taking screenshots to review if your environment supports it —
   > **a picture is worth 1000 tokens**."

3. **克制原则**（L59）：Chanel 那句「出门前照镜子摘掉一件配饰」+ "Spend your boldness in one place."

4. **🔴 `## More on writing in design`（L63-71）—— 对本仓库的价值高于视觉部分**。
   这是一个**语音优先**的 App，盲人端的「界面」相当程度上就是文案与 TTS 播报：
   > "An action keeps the same name through the whole flow, so the button that says 'Publish' produces a toast
   > that says 'Published.'"
   > "Treat failure and emptiness as moments for direction, not mood… **Errors don't apologize, and they are
   > never vague about what happened.**"

   这两条直接对上本仓库的既有约束（`aidrun-error-codes` 的错误播报、SOS 文案红线、状态词一致性），
   而且比我们自己写的更凝练。**建议整节抄进 `docs/ui/design-direction.md`。**

**⚠️ 关于「AI 指纹清单」（L38-45）**：它列了 5 类具体特征，细到 hex 值——
> "1. a warm cream background (near #F4F1EA) with a high-contrast serif display and a terracotta or warm-clay
> accent (**often near #D97757 — Anthropic's own Claude-interaction accent, so on a user's brief it reads as a
> tell**); … 4. the SaaS-card kit: content chopped into identical rounded cards, one border-radius on everything
> regardless of hierarchy, the same soft grey shadow (rgba(0,0,0,.1)) under each…"

**这份清单本身在快速过时，且是 Web 语境的**。证据：HN 用户 k2so 报告官方 skill 自己产生了新指纹 ——
"From the official frontend-design skill, on multiple occasions, **unprompted**, even I received the same
warm-cream tones for different [briefs]"（[46701528](https://news.ycombinator.com/item?id=46701528)，2026-01-21）[高]，
而现在的 SKILL.md 已经把那个暖米色 + `#D97757` 写进了自己的破绽清单——**skill 在追着自己的输出打补丁**。
另一位用户 bbg2401 指出新一代指纹已经变成 Space Grotesk + 乱用的 IBM Plex Mono
（[49446935](https://news.ycombinator.com/item?id=49446935)，2026-08-26）[高]。

⇒ **别抄这份清单，抄它的方法**：iOS 版的指纹清单外面不存在，必须自己写（见 §5.2）。

### 2.2 ⛔ Web 系全家桶 —— 逐个核实后全部不适用

| 项目 | 证据 | 判定 |
|---|---|---|
| [Vercel `web-design-guidelines`](https://github.com/vercel-labs/agent-skills/blob/main/skills/web-design-guidelines/SKILL.md) | 规则源 191 行 16 类，全绑 `aria-*` / `focus-visible:ring-*` / `touch-action` / `Intl.*`；输出格式是定位到 `.tsx` 的 `file:line` | 完全不适用 |
| [`baseline-ui`](https://github.com/ibelick/ui-skills/blob/main/skills/baseline-ui/SKILL.md) | 85 行全是 Tailwind 类名（`h-dvh`、`text-balance`、`tracking-*`） | 完全不适用 |
| [`fixing-accessibility`](https://github.com/ibelick/ui-skills/blob/main/skills/fixing-accessibility/SKILL.md) | 135 行 ARIA/HTML；概念与 VoiceOver 同构但文本不可抄 | 方法论可迁移，实现不可用 |
| [`web-artifacts-builder`](https://github.com/anthropics/skills/blob/main/skills/web-artifacts-builder/SKILL.md) | 产出物是 claude.ai 单文件 HTML artifact | 完全不适用 |
| [wilwaldon/Frontend-Design-Toolkit](https://github.com/wilwaldon/Claude-Code-Frontend-Design-Toolkit) | README 735 行，对 `ios\|swift\|swiftui\|xcode\|uikit\|apple hig` 正则扫描 **0 命中** | 完全不适用 |

### 2.3 🔄 原生 iOS skill —— 09-02 的结论在这里被推翻

09-02 报告写的是「**这个生态位在 iOS 上基本空着**」，其复核触发条件之一正是「出现原生 iOS/XCUITest 而非
浏览器的 a11y skill」。**该条件已触发**。硬指标由 `gh api` 当场取（不是转述）：

| 仓库 | star | 最后 push | license | 判定 |
|---|---|---|---|---|
| [nextlevelbuilder/ui-ux-pro-max-skill](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill) | 125,726 | 2026-09-06 | MIT | **部分可用**，见下 |
| [rshankras/claude-code-apple-skills](https://github.com/rshankras/claude-code-apple-skills) | 709 | 2026-07-24 | MIT | 可用但标准低于本仓库 |
| [ehmo/platform-design-skills](https://github.com/ehmo/platform-design-skills) | 523 | 2026-03-19（半年未动） | MIT | 观望 |
| [dickwu/apple-design-skill](https://github.com/dickwu/apple-design-skill) | 330 | 2026-02-27 | **无 license** | ⛔ **不用**（无授权即无使用许可） |

**`ui-ux-pro-max` 的两个文件是真的**（自己 curl 过）：
- `data/stacks/swiftui.csv`（15,323 bytes，50 条）：逐条 Do/Don't + Swift 代码对照，
  `Applies To` 列写 `swiftui current; iOS 16+ baseline; Observation APIs iOS 17+`，`Verified At` = 2026-08-13
  —— **与本仓库部署目标 iOS 16 对得上**。但内容是 SwiftUI **工程**规范（`@State` vs `@StateObject`、
  `NavigationStack`、`@FocusState`），与已装的 `swiftui-pro` 高度重叠。
- `references/pro-rules.md`（117 行）：**这份才是真价值** ——「native/mobile app UI 交付前检查单」，
  不是 Web 换皮。它能补本仓库确实没有的 3 条：
  - **图标对比 ≥3:1**（"Meaningful icons and control boundaries need at least 3:1"）——
    本仓库 `AppColors` 只验了文本 4.5:1，**图标/控件边界从没验过**；
  - **状态对比一致性**（"Keep pressed/focused/disabled states equally distinguishable in light and dark"）——
    本仓库从没在明暗两套下分别验过按下态；
  - **safe-area 合规**（"Placing fixed CTA bars outside safe areas"）—— 本仓库有底部常驻求助条，
    这正是记忆 `snapshot-timeout-means-a-system-app-took-over` 里那次误触的物理成因。

**`rshankras` 的 `skills/ios/`**（183 个 SKILL.md，ios 下 10 个，含 `run-device` / `assistive-access` /
`ipad-patterns`）：[`ui-review/SKILL.md`](https://github.com/rshankras/claude-code-apple-skills/blob/main/skills/ios/ui-review/SKILL.md)
的反模式清单原文是「硬编码颜色 `.foregroundColor(.black)` / 固定字号 `.font(.system(size: 14))` /
触达 <44pt / 直接用 `UIColor`」。
⚠️ **这些标准低于本仓库现行标准**：盲人端主按钮要求 ≥64pt（不是 44），`AppColors` 已按 WCAG 相对亮度公式
在四种明暗组合上实测 ≥4.5:1 并有 `AppColorContrastTests` 钉住。**照单装上等于引入一套更松的标准**，
而它还会把 `.claude/skills/ui-review/` 下的 `hig-checklist.md` 一起拉进上下文。

### 2.4 ⛔ Figma → SwiftUI：方向不对，且门槛在 Xcode 27 beta

[Figma 官方 SwiftUI Code Connect 文档](https://developers.figma.com/docs/code-connect/swiftui/)确认支持存在，
但走的是**人工把每个 Figma 组件映射到具体 `.swift` 文件**的 Code Connect 机制；
[Xcode 集成文档](https://help.figma.com/hc/en-us/articles/41061095668759-Xcode-and-Figma-Set-up-the-MCP-server)
原文：**"The Figma MCP server is only supported in the Xcode 27 beta app."** [高]
官方 [server-returning-web-code](https://developers.figma.com/docs/figma-mcp-server/server-returning-web-code/) 还写着
默认输出 "resembles react-like code because AI agents are commonly trained on large amounts of web-based data"。
⇒ 且方向是「设计稿 → 代码」，解决不了「已实现的界面长什么样」。**不用。**

---

## 3. 方法论：两派之争，和它们各自对的场景

### 3.1 官方对「AI 味」的解释（不是玄学，是采样分布）

> "During sampling, models predict tokens based on statistical patterns in training data. **Safe design
> choices–those that work universally and offend no one–dominate web training data.**"
> — [Improving frontend design through Skills](https://claude.com/blog/improving-frontend-design-through-skills) [高]

同篇明确说这套方法不限于前端：「Any domain where Claude produces generic outputs despite having more
expansive understanding is a candidate for Skill development.」

### 3.2 官方 best practices 的视觉验证循环（逐字）

来自 [code.claude.com/docs/en/best-practices](https://code.claude.com/docs/en/best-practices) [高]：

> **Give Claude a way to verify its work** — "Give Claude a check it can run: tests, a build, a screenshot to
> compare. It's the difference between a session you watch and one you walk away from."
>
> "Claude stops when the work looks done. **Without a check it can run, 'looks done' is the only signal
> available, and you become the verification loop**: every mistake waits for you to notice it."
>
> Verify UI changes visually —
> Before: *"make the dashboard look better"*
> After: *"[paste screenshot] implement this design. take a screenshot of the result and compare it to the
> original. **list differences and fix them**"*

⚠️ 注意最后一句的形状：**不是「看看好不好看」，是「列出差异并修掉」** —— 它把一个无判据的审美问题
转换成了一个有判据的比对任务。这是整份调研里最可操作的一条。

### 3.3 争议：「给方向」vs「逐条点名拒绝」

这是本轮唯一一个真正有分歧的问题，两派都有一手证据，**不要合并成一句话**。

**A 派：不要过度指定，给方向**
- 官方 SKILL.md 本身偏 A 派：要求先 brainstorm「a short design plan」，强调是
  "a choice made for this specific brief"，而不是逐条列参数。
- HN 用户 soared 分析得很准：skill "is mostly **principle-based and evocative**, which is brilliant when you
  think about it. It maintains just the right balance to fuel creativit[y]"
  （[46700764](https://news.ycombinator.com/item?id=46700764)）[高]
- 论据核心：给太细的规格会把模型锁死在你写的那几个数字上，牺牲整体连贯性。

**B 派：必须逐条点名拒绝默认值**
- 最硬的一条来自 vunderba —— 他正是那份「1590 个 Show HN 提交 AI 设计打分」实证研究的作者本人：
  "I've found that the more **specificity** you add to your prompt and less freedom you give Claude Code to
  kind of just 'do its own thing', the better your results will be."
  （[47865413](https://news.ycombinator.com/item?id=47865413)，2026-04-22）[高——发言者是数据第一作者]
- 官方 SKILL.md 的 L38-45 自己就是逐条点名（连 hex 都点了），说明官方也在用 B 派手段。

**第三个声音：官方 skill 可能两头不靠**
- rafram: "Have you actually read the frontend design skill? **It's placebo at best.** Very short and barely
  focused on design"（[49330455](https://news.ycombinator.com/item?id=49330455)，2026-08-17）[高]
- rafram（另一帖）: "lots of guides recommend blindly, in classic **LLM cargo-cult fashion**. It doesn't say
  what people think it does."（[49038246](https://news.ycombinator.com/item?id=49038246)）[高]
- duffycommaryan: "The frontend-design skill **defeats its own purpose** imo. The design equivalent of
  'it's not x, it's y.'"（[48508011](https://news.ycombinator.com/item?id=48508011)）[高]
- efficax: "it's remarkable how **easy it is to identify websites built with the 'frontend-design' skill**"
  （[48497957](https://news.ycombinator.com/item?id=48497957)）[高]
- skiing_crawling: "some skills don't even describe exactly what steps to take… They just kind of give a
  **motivational speech** which I guess primes the model"（[48140242](https://news.ycombinator.com/item?id=48140242)）[高]

**分歧点判定**：两派管的是**流程的两个不同环节**，不是互斥选项 ——
A 派管**创作自由度**（给语境框架，让模型自己决定视觉落地）；B 派管**默认值排除**（模型有极强的统计学
回归倾向，不点名就会被悄悄拉回安全区）。
⇒ **本项目适用 B 派为主**：因为痛点是「已经知道不满意」而不是「从零探索方向」，
而且盲人 App 的约束（超大触达、极高对比、单任务一屏）本身就与「通用好看」冲突，必须显式声明。

### 3.4 最实用的一条正面实践（HN 一手）

> "what I find works best is to **point Claude at a design system documentation website**"
> — ageitgey（[48475829](https://news.ycombinator.com/item?id=48475829)）[高]

对本仓库的等价物：`docs/ui/reference-screenshots/`（12 个竞品，**89 张 PNG + 23 张 JPG**）
+ `blind-ui-visual-benchmark-20260808.md` 的尺寸基线。**素材早就在仓库里，只是从没被用于设计决策**
（`ui-reference-audit.md` 审的是旧 Flutter 版，不是这批竞品图）。

### 3.5 明确不适用于原生 iOS 的方法（别照抄）

1. **Inter / Roboto 禁令无意义** —— iOS 默认排版是 San Francisco，那份 AI 指纹清单里点名的字体全是 Web 字体。
   iOS 版的等价指纹（滥用 `.blue`、清一色系统按钮、SF Symbols 堆砌但无层次）**外面没有实证清单**。
2. **玻璃拟态的结论相反** —— Web 语境里 glassmorphism 是 AI 味；iOS 26 的 Liquid Glass 是 Apple 官方方向。
   照抄 Web 结论会做出反平台的判断。
3. **8px 网格要换算** —— iOS 是 pt 且要随 Dynamic Type 缩放，不能整段搬 Web 的「锁死 8px」建议。
4. **所有公开方法论都不覆盖「美观 + 无障碍同时满足」** —— 中英文全部资料讨论的「设计质量」都是
   「好不好看 / 有没有辨识度」，没有一篇讨论 AI 生成的界面对 VoiceOver 与低视力用户是否达标。
   讽刺的是 HN 上 freedomben 夸完一个用了 frontend-design skill 的站，紧接着说
   "The text is really **small and impossible to read** at regular zoo[m]"
   （[48278342](https://news.ycombinator.com/item?id=48278342)）[高] —— 审美方案自己制造了无障碍缺陷。
   **这块是本仓库必须自己摸索的部分，抄不到。**

---

## 4. iOS 视觉闭环：技术通道与失效条件

### 4.1 XcodeBuildMCP 拿不到真机截图（官方 JSON 原文 + 本会话实证）

仓库已从 `cameroncooke` 转到 [getsentry/XcodeBuildMCP](https://github.com/getsentry/XcodeBuildMCP)。
[官方工具目录](https://xcodebuildmcp.com/docs/tools) 的分组定义逐字如下 [高]：

```json
{"id":"ui-automation","title":"UI Automation",
 "description":"UI automation and accessibility testing tools for iOS simulators...",
 "tools":["snapshot_ui","wait_for_ui","batch","tap","touch","long_press","swipe","drag",
          "gesture","button","key_press","key_sequence","type_text","screenshot"]}
```

`screenshot` / `snapshot_ui` **只在 `ui-automation` 分组**，而该分组 description 写死 "for iOS simulators"；
`device` 分组的工具列表里**没有任何截图工具**。
**本会话交叉验证**：当前可用的 XcodeBuildMCP 工具正是 `build_device / test_device / list_devices /
install_app_device / launch_app_device / …`，与官方 `device` 分组逐字对应，确实不含 `screenshot`。
⇒ **模拟器不可用 = XcodeBuildMCP 这条截图路对本仓库永久关闭。**

### 4.2 `xcresulttool export attachments` —— 本仓库已有的那条路是对的

本机 Xcode 26.2 实测 `--help` 原文：
```
USAGE: xcresulttool export attachments [--test-id <test-id>] [--schema]
       [--schema-version <schema-version>] --path <path> --output-path <output-path> [--only-failures]
```

三条实测结论 [高]：
1. **它不在 Xcode 16 的废弃名单里** —— 被废弃的是 `get object` / `export object`，本仓库用的
   `export attachments` 和 `get test-results summary` 都不受影响。
2. **Apple 自己的废弃提示有两处错**：提示说改用 `xcresulttool get attachments`（`get` 下根本没有这个子命令，
   实际在 `export` 下）、说改用 `get test-report`（真实名是 `test-results`，
   [flutter#151502](https://github.com/flutter/flutter/issues/151502) 独立记录了同一个 typo）。
3. 🔴 **假阳性风险**：没有任何匹配附件时 **exit code 仍是 0**，只写一个空的 `manifest.json`。
   本仓库 `device-test.sh:190` 已经用文件计数规避（`find … ! -name manifest.json | wc -l`）——
   但**别处复制这段命令时极易漏掉这一步**。

### 4.3 其余通道逐条否掉

| 通道 | 否掉理由 |
|---|---|
| `swift-snapshot-testing` | 真机跑直接 `Operation not permitted`（sandbox），[issue #379](https://github.com/pointfreeco/swift-snapshot-testing/issues/379) **至今 open**；而它给的变通方案（写 `XCTAttachment` 再从 `.xcresult` 抠）**就是本仓库已经在做的事** ⇒ 叠这层是纯重复。另外官方 README 警告基线必须同一台模拟器/同一 OS 比对，我们有两台真机，基线管理成本极高 |
| `ViewMonitor`（721★） | 读完 README：是**人工点按**的应用内叠加层（"with a few taps"），全文 0 处 export/JSON/API ⇒ Claude 拿不到任何东西；且依赖私有 API 只能进 Debug 构建 |
| Figma MCP | 见 §2.4，方向不对 + Xcode 27 beta |
| mcpmarket 一类的 "Visual QA Validator" | 聚合站条目，无可验证背书 [低]，不采信 |

### 4.4 🆕 观望项：Xcode 26.3 的官方 `xcrun mcpbridge`

[Apple 官方文档](https://developer.apple.com/documentation/Xcode/giving-external-agents-access-to-xcode) 给出的
确切命令 [高]：
```
claude mcp add --transport stdio xcode -- xcrun mcpbridge
```
[Xcode 26.3 发布说明](https://developer.apple.com/documentation/xcode-release-notes/xcode-26_3-release-notes)：
"Xcode 26.3 introduces support for agentic coding… makes its capabilities available through the Model Context
Protocol"。

**本机实测：Xcode 26.2，`xcrun mcpbridge` 不存在**（`xcrun: error: unable to find utility "mcpbridge"`）。

三条限制（升级前必须知道）：
1. `RenderPreview` 这个工具名与「能返回渲染后的 SwiftUI preview」这个能力，**Apple 自己的文档没有公开
   工具清单**，只有第三方印证（如 [PreviewsMCP README](https://github.com/obj-p/PreviewsMCP)）[中]；
2. 它 **tethered to a live GUI Xcode**，受 macOS Automation/TCC 门控，**无头/CI 不可用**；
3. **`RenderPreview` 能否跟随真机 run destination 是推断，不是核实过的事实** —— 若它实际走模拟器，
   则本仓库因高德无 arm64-sim slice 依然用不了。⚠️ **升级 Xcode 前不要把它写进任何计划。**

### 4.5 最值钱的一条风险结论

**所有通道共同的盲区不是「拿不拿得到图」，而是「拿到的是不是生产形态」。**
UI 测试构建永远没有高德 key，地图一律降级成占位图（记忆 `ui-test-defaults-verify-the-degraded-path`）。
⇒ 任何「Claude 看了截图说没问题」的结论，**汇报时必须附一句：这是测试构建（降级路径）下的画面**。

---

## 5. 本仓库对账：已有什么、真正缺什么

### 5.1 已有的（比预期强，别重复造）

| 已有 | 位置 | 备注 |
|---|---|---|
| 颜色 token + WCAG 实证 + 自动测试 | `blindRun/Core/DesignSystem/AppColors.swift`（110 行） | 每个色值带四种明暗组合 ≥4.5:1 的实测，`AppColorContrastTests` 钉住。**质量高于所有外部 skill 的要求** |
| 字体语义函数 | 同上 `:91-107` | `largeTitle/title/body/caption/primaryButton` |
| 三个共享组件 | `HighContrastText` / `PrimaryButton` / `ReadableContentColumn`（共 295 行） | |
| 逐页功能规格 | `docs/ui/ui-handoff-ios.md`（67.5K） | 目标/内容/按钮/状态/TTS/VoiceOver/布局建议 |
| UI 评审清单 | `docs/ui/ui-review-checklist.md`（153+ 行） | 已含 64pt 触达、每屏单任务、≥20pt body |
| 竞品参考图 | `docs/ui/reference-screenshots/` | 12 个产品，**89 PNG + 23 JPG，Claude 可直接 Read** |
| 尺寸视觉基线 | `docs/research/blind-ui-visual-benchmark-20260808.md` | 全宽圆角矩形、主按钮占内容区 ~75% |
| 无障碍审计 7 类全开 | `blindRunUITests/AccessibilityAuditTests.swift:737-740` | 09-02 的建议已落地 |
| 截图导出 | `scripts/device-test.sh:188-196` | 09-02 的建议已落地（含 manifest 归属、失败不改结论） |

### 5.2 真正的三个缺口

**🔴 缺口 A：没有「审美方向」的声明。**
`ui-handoff-ios.md` 67.5K 逐页回答了「这页**要有什么**」，但全文没有一句回答「它**该长什么样、为什么**」。
官方 skill 的整套机制建立在「先有 brief 与 design plan」之上——**没有 brief，两遍工作法的第一遍就不存在**，
模型每次都从统计默认值起步。这是「设计得没想象中好」最直接的结构性原因。

**🟡 缺口 B：间距 / 圆角 / 动效时长没有 token。**
颜色和字体有，但 37 个视图文件里 **1169 处**视觉常量（`.padding(` / `cornerRadius` / `RoundedRectangle` /
`.font(`）绝大多数是就地硬编码，`enum Spacing|Metrics|Layout` 全仓 **0 处定义**。
讽刺的是**已装的 `swiftui-pro` 自己就在建议这件事**（`references/design.md:5`）：
> "Prefer to place standard fonts, sizes, colors, **stack spacing, padding, rounding, animation timings**, and
> more into a shared enum of constants, so they can be used by all views."

同文件 `:30` 还有一条更直接的：`Avoid hard-coded values for padding and stack spacing`。
**同屏间距不一致正是「说不出哪里丑」的最常见来源**，而且它对低视力用户是实打实的可用性问题（节奏混乱）。

**🟡 缺口 C：视觉闭环最后一步没验证，且拍的地方不对。**
- 导出代码昨天（commit `b37e71b`）才落地，**本机零 `.xcresult`、零 `attachments/` 目录**
  ⇒ 这条链**从没被验证过产出任何一张图**。按记忆 `claimed-fallback-may-not-exist-in-release` 的判据，
  在跑出那行 `附件已导出（N 个）` 之前不能宣称它通。
- 实测 `attachScreenshot` 共 **10 处，全部在 `blindRunUITests.swift`**；
  **`AccessibilityAuditTests.swift` 一处都没有** ⇒ 最容易出视觉问题的三条横屏用例、
  以及 AX5 大字号那批用例，**跑完一张图都不留**。

---

## 6. 建议的开发流程

分四层，**按性价比排序，前两层是重点**。不要一次全上。

### 层 0 —— 改 UI 时的 prompt 三件套（零成本，下次就能用）

改任何界面前，把这三样贴进 prompt（缺一件效果就打折）：
1. **视觉基线**：`docs/research/blind-ui-visual-benchmark-20260808.md` 的规格（主按钮占内容区 ~75%、
   次级操作整行堆叠）；
2. **参考图**：从 `docs/ui/reference-screenshots/` 挑 1–2 张同场景的竞品图（我能直接 Read PNG）；
3. **逐条拒绝清单**（层 1 产出后就用那份）。

然后用官方那句被验证过的写法收尾，**不要写「好看一点」**：

> [贴截图] implement this design. take a screenshot of the result and compare it to the original.
> **list differences and fix them**

### 层 1 —— 写一页 `docs/ui/design-direction.md`（最高性价比）

**一页，不是第二个 67K**。内容就是官方两遍工作法要求的四件事 + 一件本仓库特有的：

| 节 | 写什么 | 本仓库现状 |
|---|---|---|
| Color | 4–6 个具名色值 | **直接引用 `AppColors`**，不要重写 |
| Type | 字体角色与层级 | **直接引用 `AppColors.body()` 那组** |
| Layout | 一句话布局概念 + ASCII 线框 | 需要新写（视觉基线可作输入） |
| Principles | 这个 App 独有的判断依据 | 需要新写 |
| **反指纹清单（iOS 版）** | **逐条点名拒绝** | **必须自己写，外面不存在** |

反指纹清单的写法示例（按 §3.3 的 B 派，点名而非泛指）：
> 不要清一色 `.blue` 强调色；不要每个卡片同一个 `cornerRadius` 无视层级；
> 不要用 SF Symbols 堆装饰（每个图标要么有 `accessibilityLabel` 要么 `accessibilityHidden`）；
> 不要 `.font(.caption2)`（`swiftui-pro:32` 明确点名）；不要在盲人端用非用户触发的动效。

**另外把官方 SKILL.md 的 `## More on writing in design` 整节抄进来**（§2.1 第 4 点）——
对一个语音优先的 App，这节比视觉部分更值钱。

### 层 2 —— 补 `AppSpacing`（补 token 层的缺口 B）

在 `blindRun/Core/DesignSystem/` 加一个 `AppSpacing.swift`（**几十行，不是框架**），
把间距/圆角/动效时长收成具名常量，然后**只在新写和改到的视图里替换**——不要全仓 1169 处一次性重构。

留一个能跑的 check：仿照 `AppColorContrastTests` 的做法，加一条断言「间距取值只能来自这张表」的测试，
或者按 `AGENTS.md` §1.1 在 `guard.mjs` 加一条守卫拦新增的裸数字 padding。
**没有 check 的 token 层三个月后就会被绕过。**

### 层 3 —— 把截图闭环真正接通（缺口 C）

1. 下次跑真机测试时**确认那行 `附件已导出（N 个）`，N 应该 ≥10** —— 在此之前这条链是「已实现，未验证」；
2. 给 `AccessibilityAuditTests.swift` 的横屏 / AX5 用例补 `attachScreenshot`（现在 0 处，正是最该拍的地方）；
3. 跑完让 Claude 逐张 `Read` 那些 PNG，并在结论里**强制注明「测试构建 / 降级路径」**（§4.5）。

### 层 4 —— 观望，不要现在做

- **Xcode 26.3 的 `xcrun mcpbridge`**：本机 26.2 还没有；且 `RenderPreview` 能否跟随真机是推断。
  升级后先验这一条再谈。
- **选装 `ui-ux-pro-max` 的 `pro-rules.md`**（117 行，MIT）：只为那 3 条本仓库没有的检查
  （图标对比 3:1、状态对比明暗一致、safe-area）。**只取这一个文件，不要装整个 skill。**

### ⛔ 明确不要做的

| 不要做 | 理由 |
|---|---|
| 装 Vercel / baseline-ui / web-artifacts-builder / Frontend-Design-Toolkit | 全 Web，§2.2 |
| 装 `dickwu/apple-design-skill` | **无 license** |
| 整装 `rshankras`（183 个 SKILL.md） | 标准低于本仓库（44pt vs 64pt）+ 上下文成本，与 09-02 否掉 Axiom 同理 |
| 引入 `swift-snapshot-testing` | 真机 sandbox 不允许，且其变通方案 = 本仓库已有做法 |
| 上 Figma MCP | Xcode 27 beta + 方向不对 |
| 把官方那份 AI 指纹清单（暖米色/#D97757/SaaS 卡片）当检查表照抄 | Web 语境，且它自己在快速过时（§2.1） |
| 再写一个 `aidrun-*` skill 装设计规则 | 缺的是**方向声明**和**检查**，不是第二份文档（`AGENTS.md` §1） |

---

## 7. 反对意见（这个建议在什么情况下是错的）

1. **如果「不满意」的其实是信息架构而不是视觉。**
   本仓库的界面约束（超大按钮、单任务一屏、深色高对比）本身就与「通用好看」正交——
   盲人端首页按视觉基线做完，对明眼人看仍会显得「土」，但那是**正确的**。
   如果真正的不满是「志愿者端信息太挤」这类结构问题，那该动的是 `ui-handoff-ios.md` 的页面规格，
   写十份 design-direction 也没用。**动手前先分清是哪一种。**

2. **如果 design token 层被当成目标而不是手段。**
   `AppSpacing` 的价值全在「同屏一致」，如果只是把 `.padding(16)` 换成 `.padding(AppSpacing.md)` 而取值表
   本身是随手定的，那是纯搬运，还多了一层间接。**没有配套 check 的 token 层是负资产。**

3. **官方 skill 可能真的没那么有用。** §3.3 的三位 HN 用户（rafram / duffycommaryan / efficax）说得不轻，
   而且 efficax 那条「一眼认出用了这个 skill」意味着**它自己就是新指纹的来源**。
   本报告建议的是「抄它的流程（两遍工作法 + 截图自评 + 写作原则）」而**不是装它**——
   如果哪天发现照做之后界面反而更像模板，应该退回到「只用参考图锚定 + 逐条拒绝」。

4. **125,726 star 不构成质量证据。** `ui-ux-pro-max` 的 star 数高得异常（比 Claude Code 本体量级还大），
   本报告只采信自己 curl 过的那两个文件的**内容**，不采信它的流行度。

---

## 8. 被否掉的方案留档

| 方案 | 否掉理由 | 什么情况下重新考虑 |
|---|---|---|
| Web 系 design skill 全家桶 | 检查对象在 iOS 上不存在 | 项目出 Web 端 |
| Figma Dev Mode MCP | Xcode 27 beta + 要手工 Code Connect 映射 | Figma 支持稳定版 Xcode |
| `swift-snapshot-testing` | 真机 sandbox 拒写 + 变通方案与现有重复 | issue #379 关闭 |
| `ViewMonitor` | 人工点按、无程序化输出、仅 Debug 构建 | 它加上导出 API |
| `dickwu/apple-design-skill` | 无 license | 加上 license |
| 整装 `rshankras` / `ehmo` | 标准低于本仓库 + 上下文成本 | 只按需取单个 reference 文件 |
| 现在上 `xcrun mcpbridge` | 本机 Xcode 26.2 没有该命令 | 升级到 26.3+ 后先验「能否跟随真机」 |

---

## 附：URL 核验（2026-09-07 实跑）

```bash
grep -oE 'https?://[^)"< ]+' docs/research/ai-ui-design-workflow-for-swiftui-20260907.md \
  | sed 's/[.,]$//' | sort -u | while read -r u; do
      c=$(curl -sIL -o /dev/null -w '%{http_code}' --max-time 12 "$u"); [ "$c" = 200 ] || echo "$c $u"; done
```

**输出：11 条非 200，全部是 `news.ycombinator.com/item?id=…`，返回码 405。**

逐条处理结果：**405 = Method Not Allowed，HN 不接受 HEAD 请求**，是方法不匹配不是死链
（同类坑见记忆 `url-check-false-flags-trailing-paren` 的第三种：只认 GET 不认 HEAD）。
改用 GET 重验 11 条：2 条 200、9 条 429（限流），**0 条返回 "No such item"** ⇒ 全部真实存在。
另外这 11 个 item id 不是搜索结果里抄的，是从 HN Algolia API 的 `objectID` 字段直接取的，
评论作者、日期、正文均在同一次响应里拿到。

**其余 URL（GitHub / GitHub raw / Apple 开发者文档 / Figma 开发者文档 / claude.com / code.claude.com）
全部 200。**
