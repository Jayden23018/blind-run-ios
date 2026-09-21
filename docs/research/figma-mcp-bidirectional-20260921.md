# Figma MCP 与 iOS 设计流程：订正 09-07 报告的 §2.4（2026-09-21）

**问题**：Figma 适合做本项目的 iOS UI 设计吗？能不能把 Claude Code 和 Figma 连起来？
`ai-ui-design-workflow-for-swiftui-20260907.md` §2.4 把它否掉了，这个结论还作数吗？

**一句话结论**：**一半作数，一半是误读，而误读的那一半正好是决定性的那一半。**
09-07 报告引的原文没错（Figma help center 今天仍逐字写着
"The Figma MCP server is only supported in the Xcode 27 beta app"），但它把这条限制当成了
**整个 Figma 路线**的门槛 —— 那句话只约束「**在 Xcode 里**用」。Figma MCP 是远程 HTTP server
（`https://mcp.figma.com/mcp`），**Claude Code 自己就是 MCP 客户端，不经过 Xcode**。
同时 09-07 的第二条否决理由（「方向是设计稿→代码，解决不了已实现的界面长什么样」）
**已被官方推翻**：Figma 官方仓库 `figma/mcp-server-guide` 现在有一个 `figma-swiftui` skill，
描述逐字写着 "in EITHER direction"，且有独立的
`references/code-to-design.md` 专门讲**把 SwiftUI views / screens / tokens 推回 Figma**。
🔴 **真正的门槛换成了两条，都不是技术问题**：① Figma **seat 等级** ——
Starter 计划或 View/Collab seat **每月只有 6 次工具调用**；② write-to-canvas 仍是 **Beta**，
且官方明说 "will eventually be a usage-based paid feature"。

---

## 1. 核实口径

- 一手文件全部自己 `curl` 原文，不经小模型转述：`figma/mcp-server-guide` 的
  `skills/figma-swiftui/SKILL.md`、`skills/figma-swiftui/references/code-to-design.md`、`README.md`。
- Figma help center 的 Xcode 文章走 `WebFetch`，要求逐字引用版本限制句。
- **本机实测**：`xcodebuild -version` → **Xcode 26.2 (17C52)**；`xcrun mcpbridge` 仍
  `unable to find utility`（与 09-07 报告一致，14 天内没变）。
- ⚠️ **本轮没有实际连接过 Figma MCP server**，也没有本项目的 Figma 账号信息 ⇒
  「连上之后好不好用」「我们的 seat 够不够」全部是**未验证**的，见 §5。

---

## 2. 订正了什么：作用范围，不是事实

09-07 报告 §2.4 的原文引用是准确的，两句话我都复核过仍然逐字成立：

| 出处 | 逐字原文 | 今天还成立吗 |
|---|---|---|
| [Figma help center](https://help.figma.com/hc/en-us/articles/41061095668759-Xcode-and-Figma-Set-up-the-MCP-server) | "The Figma MCP server is only supported in the Xcode 27 beta app." | ✅ 仍成立（今天抓的） |
| [官方文档](https://developers.figma.com/docs/figma-mcp-server/server-returning-web-code/) | 默认输出 "resembles react-like code because AI agents are commonly trained on large amounts of web-based data" | ✅ 仍成立，但**有解**（见 §3 第 1 点的 `clientFrameworks`） |

**误读在于**：第一句约束的是 **Xcode 作为 MCP 客户端**。而 `README.md` 的安装章节逐字列的客户端是
VS Code / Cursor / Claude Code 等，服务端是一个 HTTP endpoint：

```json
{ "servers": { "figma": { "type": "http", "url": "https://mcp.figma.com/mcp" } } }
```

Claude Code 支持 HTTP MCP（本仓库 `.mcp.json` 里的 firecrawl 就是这种）⇒
**「要 Xcode 27 beta」对我们这条路完全不适用。** 这是 09-07 那条否决里最贵的一处错
—— 它让人以为整条路被堵住了，于是不会再去看第二个方向。

> 同型先例：记忆 `symptom-match-is-not-mechanism-match`（症状/引文对得上，机制/作用范围反了）。
> 判据是一样的：**引文正确不等于推论正确**，引一句限制条款时要问「它约束的是哪个组件」。

---

## 3. `code → design` 这条路真实存在，且比预期完整

[`skills/figma-swiftui/SKILL.md`](https://github.com/figma/mcp-server-guide/blob/main/skills/figma-swiftui/SKILL.md)
的 frontmatter 逐字（自己 curl 的）：

> description: "SwiftUI ↔ Figma translation. Use whenever the user mentions Swift, SwiftUI, iOS, iPhone,
> or iPad — **in EITHER direction** — translating a Figma design into SwiftUI (design → code), or
> **pushing SwiftUI views / screens / tokens back into a Figma file (code → design)**."

`references/code-to-design.md` 里对本仓库直接有用的四条（均为原文要点，不是我的推断）：

1. **框架要显式指定**：`get_design_context` 要传 `clientLanguages: "swift"` 与
   `clientFrameworks: "swiftui"`，"so the response is framed as Swift"
   ⇒ 09-07 担心的「默认吐 React」是**默认值问题，不是能力上限**。
2. **HIG 语义色按 token 走不按 hex 走**，给了完整映射表（`Color(.systemBackground)` ↔
   `background/primary`、`Color(.separator)` ↔ `separator/non-opaque` …），并逐字要求
   "Never paste a hex"。🔑 **这正好对上本仓库的 `AppColors`** —— 我们的色板本来就是语义化的，
   推到 Figma 会落成 variable collection 而不是散色值。
3. **Apple 官方 Figma 库是现成的**：文中点名 Apple 以 Community library 形式发布
   *iOS 18 and iPadOS 18* / *iOS and iPadOS 26* / *watchOS 26* / *visionOS 26*，
   组件命名稳定（`Navigation Bar - iPhone (Compact Size Class)`、`Tab Bar - iPhone`、`Row`、
   `Segmented Control`…），还有 **Product Bezels**（按真机尺寸的外壳，iPhone 16 = 393×852、
   iPhone 16 Pro = 402×874），并逐字警告 "Sizing the screen at 393 and dropping in a 402-wide
   nav bar produces a misaligned design"。
4. **SwiftUI → Figma 的结构映射表**逐条给了（`NavigationStack` → 大标题 nav bar、
   `TabView` → 底部 tab bar 且每个 tab 的 child 成为独立 frame、`List { Section }` → 分组表格
   **且最后一行不画分隔线**、`Spacer()` → `SPACE_BETWEEN` 而不是实体节点、
   `VStack/HStack` → `createAutoLayout` 且 "never absolute x/y"）。
   这个细致程度（连 `List` 末行分隔线都写了）说明它不是营销页，是真做过。

---

## 4. 🔴 真正的门槛：seat 等级与 Beta 状态

`README.md` 逐字（这是本轮最该记住的一段）：

> "Users on the **Starter plan** or with **View or Collab seats** on paid plans will be limited to
> **up to 6 tool calls per month**."
> "Users with a Dev or Full seat on the Professional, Organization, or Enterprise plans have per minute
> rate limits, which follow the same limits as the Tier 1 Figma REST API."

**每月 6 次调用在任何实际工作流下等于不可用** —— 光是「读一个 frame + 推一个屏回去」就会用掉两三次。
另外两条：

- **write-to-canvas 是 remote server only**（正是 Claude Code 连的那个），且
  "These skills are currently available as a **Beta** feature"；
- 官方明说 "The write to canvas feature will **eventually be a usage-based paid feature**,
  but is currently available for free during the beta period."

⇒ **判定：技术上通，商业上取决于 seat。** 决定要不要走这条路之前，先回答一个问题：
**这个项目的 Figma 账号是什么 seat？** 免费 Starter ⇒ 别接，6 次/月做不了任何事。

---

## 5. 对本仓库的建议（分三种用途，判定不同）

| 用途 | 判定 | 理由 |
|---|---|---|
| **A. 画新功能的设计稿给人看**（如地图页） | ✅ **直接用，且不需要接 MCP** | 导出 PNG 我能直接 `Read`。这是零风险零成本的一条，本仓库做竞品参考图走的就是这条路 |
| **B. Figma 稿 → SwiftUI 代码** | 🟡 **可以试，但不是瓶颈** | 本仓库的瓶颈从来不是「把稿翻成代码」，是**没有稿、也没有审美方向**（`design-direction.md` 就是补这个）。先有方向再谈自动翻译 |
| **C. 现有 SwiftUI → Figma**（反向导入来改） | 🟡 **最有价值但先算成本** | 它能一次性把现有界面变成可视化的、可并排比较的画布 —— 这正是「说不出哪儿丑」最需要的东西（记忆 `flexible-spacer-steals-half-the-row` 那类问题只能目视）。但要 Dev/Full seat |

**不变的一条**：无论走哪条，`design-direction.md` 的四步流程（出 plan → 自审是否是默认值 →
写代码 → 截图对比「列出差异并修掉」）都是前置。Figma 换掉的只是第 4 步的**载体**，
不是流程本身。09-07 报告最核心的结论「缺的是流程不是工具」**没有被本轮推翻**。

---

## 6. 反对意见（什么情况下本轮建议是错的）

1. **如果 seat 是 Starter，本篇 §3 全部作废** —— 6 次/月连一次完整往返都跑不完。
   那时唯一成立的是 §5 的用途 A（导出 PNG），而那条根本不需要本篇。
2. **`code → design` 可能做出一份必然过期的第二源。** 本仓库栽过这个跟头（`AGENTS.md` §9：
   「写『以 X 为准』再抄一份 X，等于制造一个必然过期的第二源」）。推到 Figma 的界面
   **一旦被当成设计源真相**，就会与代码漂移 ⇒ 用它做**一次性的看图工具**可以，
   做**长期维护的设计系统**要先想清楚谁是源。
3. **Beta + 未定价**。官方明说 write-to-canvas 以后要收费。把流程建在一个未定价的 Beta 上，
   等于给自己埋一个迁移成本。
4. **本轮没有实测连接。** 所有「能做」都来自官方文档与 skill 原文，**没有一次真实的
   `use_figma` 调用**。按本仓库的口径这属于「已核实文档，未验证行为」。

---

## 7. 被否掉的方案留档

| 方案 | 否掉理由 | 什么情况下重新考虑 |
|---|---|---|
| 在 **Xcode** 里接 Figma MCP | 逐字要求 Xcode 27 beta，本机 26.2；且本仓库不需要（Claude Code 直连） | 用户想在 Xcode 里用 agent 且升到了 27 |
| 现在就上 `xcrun mcpbridge` | 本机 Xcode 26.2 无此命令（14 天内没变，与 09-07 结论相同） | 升到 26.3+ 后先验「能否跟随真机 destination」 |
| 把 Figma 当设计源真相长期维护 | §6 第 2 点，第二源必然漂移 | 有专职设计师维护 Figma 文件时 |

---

## 附：核实命令（可重跑）

```bash
curl -sL https://raw.githubusercontent.com/figma/mcp-server-guide/main/skills/figma-swiftui/SKILL.md | head -20
curl -sL https://raw.githubusercontent.com/figma/mcp-server-guide/main/README.md | grep -A2 'tool calls per month'
xcodebuild -version && xcrun mcpbridge --help
```
