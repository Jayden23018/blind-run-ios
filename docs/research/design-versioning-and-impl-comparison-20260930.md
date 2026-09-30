# 设计稿版本管理、设计↔实现对照、「聊天里做设计 → Claude Code 实现」的交接

调研日期 2026-09-30 · 档位 **C（三线并行）** · 三个 subagent 合计约 45 万 token · 只读研究，未改任何代码。

**方法声明**：三线内容由 subagent 抓取，主会话只对「Claude Design 没有版本历史」这一句自己抓过原文（support.claude.com 页面逐字含 `Claude Design doesn't have version history yet.`）。其余标 [高] 的是 subagent 读到官方原文的，标 [中]/[低] 的按下面分级。§9 附 URL 存活核验输出；**URL 能打开不等于结论被原文支持**，落地前引用具体数字请回原文再核一遍。

## 0. 与旧账的关系

| 旧报告 | 本轮 |
|---|---|
| [09-07 AI 界面设计流程](./ai-ui-design-workflow-for-swiftui-20260907.md)：缺的是流程不是工具；截图闭环 | **未推翻**。本轮补的是它没覆盖的两段：设计稿版本管理、设计图对照实现 |
| [09-21 Figma MCP 双向](./figma-mcp-bidirectional-20260921.md)：文档说能、未实测、seat 门槛 | **未重查**。本轮结论是不需要它：设计源是 claude.ai 的 HTML/PNG，不在 Figma |
| 09-07 说 `attachScreenshot` 在 `AccessibilityAuditTests.swift` 为 0 处 | **已过期**：现在该文件 3 处、`blindRunUITests.swift` 12 处（`grep -c` 实测），审计用例已经留图 |

## 1. 一句话结论

**版本管理这件事工具不会替你做，要在仓库里做；对照这件事不要做「逐像素」，分三层做：数值对账 + 无障碍树 + 真机截图并排、由 Claude 只列「明显差异」再由你确认。**

## 2. 本仓库现状（本轮读过的，不是估的）

- 设计交付物散在 `~/Downloads`：6 个目录 + 5 个 zip。大小（`du -sk`）：`zhumangpao-handoff` 3008KB、`-v2` 3104KB、`guide-handoff-v3` 3972KB、`ios-order-flow-handoff` 1508KB、`design_handoff_running_state` 2964KB、`run-record-handoff` **27044KB（74 张 PNG）**。
- **重复件**：`zhumangpao-handoff.zip` 与 `zhumangpao-handoff (1).zip` 逐字节相同（`cmp`）；`design_handoff_running_state 2` 与原目录仅差 8KB。
- 仓库内只有 `docs/ui/mockups/` 下 2 个目录，且**已经是对的形态**：`volunteer-profile-first-screen-20260914/README.md` 有「设计稿不是实现」声明、字段来源表、`IMPLEMENTATION-PROMPT.md`。其余设计包没走这条路。
- 「读哪份」目前只存在于记忆（如 `volunteer-order-page-v2-decisions`、`run-record-feature-decisions`），不在仓库；换机器、清下载夹、新 worktree 即断。
- 真机截图通道已在：`scripts/device-test.sh:288-289` 用 `xcresulttool export attachments` 导出。
- 设计稿与实现之间**没有任何对照记录**：`docs/ui/ui-reference-audit.md` 审计的是旧 Flutter，不是设计稿。

## 3. 共识（多个独立来源）

**3.1 官方：这条工作流是存在的，但版本管理是空白**
- Claude Design 是 Anthropic Labs 产品，2026-04-17 research preview。[官方公告](https://www.anthropic.com/news/claude-design-anthropic-labs) [高]
- 官方交接形态：Export → "Hand off to Claude Code"。[帮助中心](https://support.claude.com/en/articles/14604416-get-started-with-claude-design) [高]
- 交接包含设计文件、聊天记录、README，另给一条含 bundle URL 的 prompt 粘进本地 Claude Code。[教程](https://academy.claude.com/tutorials/using-claude-design-for-prototypes-and-ux) [高]
- **官方自认没有版本历史**，多人同时编辑也「still basic and may not work reliably」。[帮助中心](https://support.claude.com/en/articles/14604416-get-started-with-claude-design) [高]（前半句主会话已核原文）
- Claude Code 内另有 `/design`（v2.1.265+，artboards，发布成 artifact，可逐块导出 PNG/PDF）；artifact 侧每次 publish 是一个 version。[artifacts 文档](https://code.claude.com/docs/en/artifacts) [高]
- 官方对设计规范的约定：tokens 写进 CLAUDE.md 或仓库 theme 文件，优先级「你的 prompt > 你的设计系统 > 内置选择」。[同上](https://code.claude.com/docs/en/artifacts) [高]
- 官方视觉验证建议：给 Claude 一个能跑的检查，并示范「截图对比 → 列差异 → 修」。[best-practices](https://code.claude.com/docs/en/best-practices) [高]

**3.2 从业者：决策记录进 git、旧的标 Superseded 不删**
- ADR 状态含 Proposed / Accepted / Deprecated / Superseded，旧条目被取代后标记而不删除，放仓库里走 PR 评审。[Microsoft playbook](https://microsoft.github.io/code-with-engineering-playbook/design/design-reviews/decision-log/) [中]

**3.3 从业者：Design QA 先分级，不追像素**
- 工程标 ready 后设计师按清单验（规范、边界态、无障碍、响应式），问题记录并定级，非关键项可延后。[HubSpot](https://product.hubspot.com/blog/avoid-design-debt-with-better-design-qa) [中]

**3.4 只贴截图会逐轮漂移，要给结构化锚点**
- 「screenshot prompting has a ceiling」，改用 tokens + 布局清单 + 组件清单让模型自查。作者推的是自己的工具且无量化结果。[dev.to](https://dev.to/romantsisyk/claude-code-figma-a-deterministic-design-handoff-pipeline-lk3) [低]
- 「代码里改了设计源也要回改，否则漂移」。教程站一句话，无案例。[claude-code-playbook](https://claude-code-playbook.pages.dev/en/docs/level-4/claude-design-handoff) [低]
- 开放规范可参考：Google Stitch 的 DESIGN.md（YAML front matter 放 tokens、正文放理由，附 lint/diff/export；版本 `alpha`，官方自称「schema and CLI still under active development」）。[仓库](https://github.com/google-labs-code/design.md) [高]

**3.5 大模型读图测不准尺寸，有数据**
- Anthropic 文档：坐标/定位输出 "approximate"；图像会降采样（标准档长边 1568px，Claude 4.7 及以后 2576px）；有损压缩伪影会损害表现；建议小元素裁剪后再送。[vision](https://platform.claude.com/docs/en/build-with-claude/vision) [高] · [vision-coordinates](https://platform.claude.com/docs/en/build-with-claude/vision-coordinates) [高]
- 专测「从截图精确读尺寸」的基准 Pattern over Pixels：5 个前沿模型，卡片宽度平均准确率 **21.17%**、字号 **7.89%**，字号答案偏向「与相邻元素一致」的比例 **80.22%**。单篇预印本，subagent 只读到摘要页。[arXiv 2608.03691](https://arxiv.org/abs/2608.03691) [中]
- BlindTest：4 个 VLM 在简单几何任务平均 **58.07%**，最好的 Claude 3.5 Sonnet **77.84%**，形状靠近时错得多。[arXiv 2407.06581](https://arxiv.org/abs/2407.06581) [高]
- **推论（我的，不是来源原话）**：让模型判「间距差几 pt、字号差一号」是净亏；它适合发现「明显不对」。

**3.6 跨渲染器逐像素 diff 是错的**
- 同一份图换 iOS 版本、换机器就会像素不同（文字抗锯齿、重采样）；有项目因 Xcode Cloud 与本地 Mac 的重采样差异导致精确快照 CI 失败，先放 0.98 感知容差、后改固定 Xcode 与运行时版本。[PR 记录](https://github.com/IanHoar/hop-tales/pull/108) [中，单项目]
- Ash Furrow（Artsy）：iOS 版本常改文字抗锯齿，快照要绑定 iOS 版本，更新基线会带来大量图片变更，但他「no regrets」。[博客](https://ashfurrow.com/blog/snapshot-testing-on-ios/) [中]

## 4. 争议（不与共识合并）

**A. 「先写规格」算不算瀑布**——与「设计包先行」直接相关
- 反：Marmelab 迭代约 10 小时不写规格，称一个简单功能产出 "8 files and 1,300 lines"、评审要做两遍。[文章](https://marmelab.com/blog/2025/11/12/spec-driven-development-waterfall-strikes-back.html) [中]
- 反：Böckeler（Thoughtworks）说多数工具只是 spec-first，规格的长期维护策略「vague」，大上下文不等于 AI 会遵守。[martinfowler.com](https://martinfowler.com/articles/exploring-gen-ai/sdd-3-tools.html) [中]
- 正：Brooker（Kiro 团队，**有利益关系**）规格是被迭代的对象。[博客](https://brooker.co.za/blog/2026/04/09/waterfall-vs-spec.html) [低]
- HN 个人经验两边都有：有人试 Spec-Kit 几小时后发现建错了东西，有人认为规格是给模型的上下文入口。[HN](https://news.ycombinator.com/item?id=45935763) [中]

**B. 单一事实源是设计文件还是代码**
- 设计文件为源：claude-code-playbook（见 3.4）[低]。
- 代码为源：zenn 作者认为同时维护文档与代码有「cognitive load」，应让设计与实现共演化。[zenn](https://zenn.dev/cbmrham/articles/202601-spec-driven-development-skepticism?locale=en) [中]

**C. 网页版 Claude 与 Claude Code 的设计感差异从哪来**
- 一位作者称差别在指令：网页版内置 frontend-design skill、Claude Code 默认偏功能，装官方插件就追平。[baremetaldigest](https://baremetaldigest.substack.com/p/the-design-gap-between-claude-web) [中]
- 它只解释审美，不解释贴合具体稿件。**这是一个可以在本项目验证的假设，不是结论**：聊天侧与实现侧是两套默认指令。

**D. AI 视觉 diff 能降多少误报**——全是厂商自述：Percy 称审阅时间减 3 倍、滤 40% 误报；另有「像素比对误报 20–40%」来自厂商知识库。[Percy](https://www.browserstack.com/percy/visual-regression-testing) [低] · [bug0](https://bug0.com/knowledge-base/what-is-visual-regression-testing) [低]。**不采信数字**。

## 5. 工具与真机约束（C 线）

| 工具 | 依赖模拟器？ | 与本仓库的关系 | 依据 |
|---|---|---|---|
| swift-snapshot-testing（4351★，最近提交 2026-09-21） | 真机 sandbox 报错，issue #379 open | 09-07 已否决，本轮 gh 复核 issue 仍 open | [仓库](https://github.com/pointfreeco/swift-snapshot-testing) [高] |
| Emerge Tools | **是**（文档写 on a real simulator） | 不能用 | [文档](https://docs.emergetools.com/docs/ios-snapshots) [中] |
| Sherlo | 是（RN + Storybook，模拟器） | 不适用 | [官网](https://sherlo.io/) [中] |
| App Percy | 否，云端真机 | 需上传截图到云、有价格；未查 XCUITest 支持 | [文档](https://www.browserstack.com/docs/app-percy) [中] |
| Applitools Native | **未核实** | subagent 给的文档链接 404（主会话复核，GET 也 404），本轮无替代来源，其「真机是否需重签名」等说法一律不采信 | — |
| Maestro `assertScreenshot` | 官方 iOS 仅模拟器；第三方真机方案 101★ | 上游真机 PR #3100 仍 open | [博客](https://maestro.dev/blog/visual-testing) [中] · [PR](https://github.com/mobile-dev-inc/Maestro/pull/3100) [高] |
| pixelmatch（6969★，2026-09-15）/ odiff（3223★，2026-08-24） | 否，纯图片 diff | 只适合**同渲染环境同基线**；跨渲染器全屏噪声 | [pixelmatch](https://github.com/mapbox/pixelmatch) [高] · [odiff](https://github.com/dmtrKovalenko/odiff) [高] |

## 6. 反对意见（什么情况下上面的建议是错的）

1. **一人团队里，规格与索引本身的维护成本可能大于收益。** Marmelab 的「两遍评审」、HN 评论者「写规格比写代码难」的成本，在同一个人既写规格又评审规格又评审实现时全部落到自己身上。若下一阶段界面基本不再改（你说「差不多了」），补索引的价值只在防回退与防重复劳动，不是持续收益。→ 索引要保持一张表的体量，超过就说明做过头了。
2. **Design QA 清单与 token 流水线的默认前提是「设计师 ≠ 开发」且设计源是 Figma。** 你两条都不满足；HubSpot 一类来源里没有任何一篇覆盖 **VoiceOver 无障碍树**（朗读顺序、标签、动作）验收，而这恰是盲人端的主要界面。视觉对照清单会漏掉最重要的那一层。（此条是我依据来源适用范围的推断。）
3. **让大模型比对两张图可能给出虚假的安心感**：它对尺寸读得准的概率只有 21.17% / 7.89%（3.5），且倾向补全「相邻一致」的答案，会**漏报刻意的差异**。对照报告里「没发现差异」不等于没有差异。
4. **单张设计稿做基线覆盖不了 Dynamic Type AX5、横屏、明暗、iPad**：组合数成倍增长（Ash Furrow 也提到按 iOS 版本分基线会成倍增加图片）。「与设计一致」在本项目里必须先定义是哪一档。（推导，未找到直接报告。）

## 7. 没找到的（不用推测填）

- Claude/GPT/Gemini 读两张截图找间距、字号、对齐、颜色差异的**查全率、误报率**：无直接实测。上面两篇是最接近的代理指标。
- 独立开发者管理 v1/v2/v3 设计版本、标现行/废弃的具体做法：没找到一手。
- iOS/SwiftUI 场景下「设计稿对比实现」的一手案例：没找到。
- HTML 原型与 SwiftUI 渲染的系统性差异（字体渲染、safe area、连续曲线圆角、阴影、暗色）的权威文章：没找到；Apple `RoundedCornerStyle` 页抓取失败，未核实。
- Reddit（r/ClaudeAI、r/iOSProgramming）实际帖子：WebSearch 未返回，未专门试站内搜索。
- `/design-sync` 命令：一篇官方博客抓取结果提到，站内检索称无法确认，官方 commands 文档没核到 ⇒ **不采信**。
- Claude Design handoff bundle 里 README 的具体字段与目录结构：官方未公开。
- 一篇二手材料给的「MLLM as a UI Judge」精确匹配 35–38% 未能在原文核实，**未采信**。

## 8. 对本仓库的含义（建议，非已执行）

**要做的只有四件事，按顺序，前两件是基础：**

1. **一张索引表 `docs/ui/design/INDEX.md`**（每个界面一行）：现行包 · 状态（Current / Superseded）· 取代了谁 · 实现落点（Swift 文件）· 最近一次对照日期 · 已知偏差。Superseded 的行**不删**（Microsoft ADR 做法）。DECISIONS 之间冲突时「以哪份为准」写在这一列，不再只存记忆。
2. **设计包入库，沿用已有约定** `docs/ui/mockups/<topic>-<YYYYMMDD>/`（README 声明「是设计稿不是实现」+ 字段来源表 + IMPLEMENTATION-PROMPT）。迁移成本：五个 zhumangpao/running-state 包合计 14.5MB（含 `support.js` 等运行文件，挑 md + HTML + 关键 PNG 入库远小于此）；**`run-record-handoff` 27MB/74 PNG 不整包入库**，只放 DECISIONS + 4–6 张关键图 + 出处，其余留下载夹；两个重复件（`(1).zip`、`running_state 2`）直接删。
3. **对照分三层，不做跨渲染器像素 diff**：
   - **L1 数值对账**：设计包的数值表（pt、token 名）与代码里的取值比，能脚本化的（颜色、字号、间距、最小触达）做成检查。模型只做解读，不做测量。
   - **L2 无障碍树**：朗读顺序、标签、动作——已有 `AccessibilityAuditTests`（3 处留图）与 UI 测试，是本项目最重要的一层。
   - **L3 视觉**：真机截图（`device-test.sh:288-289` 已导出）与设计 PNG **缩放到同宽、并排拼成一张**、图片放文字前、加 "Image 1 / Image 2" 标签（官方 vision 文档的写法），对小元素**裁剪后再送**；让 Claude 只列「明显差异」并自分两档（A 影响正确性/违反既定需求，B 其余），你只按 A 动手。
4. **交接契约反向约束聊天侧**：让聊天里做的每个界面除图外必交四样——数值表、状态矩阵（AX5/横屏/明暗）、VoiceOver 朗读顺序与标签、「必须精确 / 可近似」两栏。同时**验证 §4-C 那条假设**：把 `docs/ui/design-direction.md` 放进 claude.ai 项目知识，看两边默认审美是否一致。

**明确不做**：Figma seat + MCP（设计源不在 Figma）、Percy / Applitools / Emerge / Sherlo（依赖云端或模拟器、且价格与适配未核）、逐像素 diff。

## 9. URL 核验

2026-09-30 对报告内 33 个 URL 跑 `curl -sIL`：31 个 200；HN 线程返回 405（拒绝 HEAD），改用 GET 复核为 200；Applitools 文档页 404（GET 同），**已删该条结论**（见 §5 表）。删后再跑一遍，输出见 PR 描述。

## 10. 复核触发条件

Claude Design 增加版本历史或 handoff 支持多版本；Claude Code 官方给出真机截图对照的做法；出现 SwiftUI 场景下「设计稿 vs 实现」的一手案例；Pattern over Pixels 一类基准出现对 Claude 4.7+ 的重测；本项目设计源迁到 Figma 或 Stitch。
