# Opus 5 的用法、effort 档位与本仓库工作流优化

**日期**：2026-09-06 · **核实通道**：Anthropic 官方文档（platform.claude.com / code.claude.com / anthropic.com）+ HN Algolia 原始评论 + 本机实测
**本机环境**：Claude Code `2.1.224`

> ⚠️ **先读这条：本报告有一份并行的姊妹篇，结论互补且有两处冲突。**
> 同一天 01:42，后端仓库落了 [`demo/docs/research/opus5-workflow-optimization-20260906.md`](file:///Users/mac/Downloads/demo/docs/research/opus5-workflow-optimization-20260906.md)，
> 查的是同一个问题。两份是**独立**做的 —— 本仓库的 `docs/research/INDEX.md` 只盖本仓库，
> 而那份落在后端仓库，所以谁都没看见谁。这本身就是 `AGENTS.md` §12 第 1 条要防的事，
> 只是它当时没跨仓库；已按 §1.1 把钩子改成两份索引都灌（PR #109）。
>
> **分工**（避免第三次重跑）：
> - **那份更强的两块**：① §3.2 收集了「更高 effort 在编码上会变差」的三个反向证据
>   （system card 的 "make more changes than the task requires"、Cognition FrontierCode 1.1 最佳分落在
>   medium、CodeRabbit 基准 xhigh 精度升但**召回降**、nitpick 4×）；② §四 **在系统提示里直接核实**了
>   官方三段 prompt 已被 `claude_code` 预设内置。本报告 §F 与 §G 已按这两条修正。
> - **本份独有**：Claude Code 侧机制（`/effort` 优先级、`ultrathink` vs `ultracode` 的官方原文）、
>   `/goal` 的完整机制、HN 45 条原始评论、以及**本仓库**的常驻上下文实测与瘦身方案。

---

## 0. 一句话结论

**本仓库现在踩的三个坑，官方 Opus 5 文档逐条点了名，而我们的规则文件正好写反了两条：**

1. **常驻上下文 21k token**（实测 53,082 字符 / 8 个文件）。官方原文：*"Bloated CLAUDE.md files cause Claude to ignore your actual instructions!"* —— 「说了不听」的第一嫌疑不是模型，是规则太长。
2. **`~/.claude/CLAUDE.md` 里「明确告诉它只报影响正确性或违反既定需求的」这条，在 Opus 5 上会主动压低 review 召回**。官方原文：*"If your review prompt says 'only report high-severity issues' or 'be conservative,' the model may follow that instruction literally and report less; ask it to report everything and filter in a separate pass instead."*
3. **effort 口径过时**：`~/.claude/CLAUDE.md` 写「整会话要高 effort 用 `/effort xhigh`」—— 那是 **Opus 4.7/4.8** 的官方起点。Opus 5 的官方起点是 **`high`（默认）**，且明说*"If you carried effort defaults over from a prior model, re-run an effort sweep on your own evals."*

另外**缺一条**全仓 0 命中的指令：**控制输出长度**。Opus 5 默认输出比历代 Opus 长，且**降 effort 不会让它变短**（官方原文，见 §A）——这正是社区抱怨最集中的一点。

---

## A. effort：官方口径（原文）

来源：[Effort](https://platform.claude.com/docs/en/build-with-claude/effort)（2026-09-06 抓取）

### A.1 五档定义（原文表）

| 档 | 官方描述 | 典型用途 |
|---|---|---|
| `max` | Absolute maximum capability with no constraints on token spending | 需要最深推理与最彻底分析的任务 |
| `xhigh` | Extended capability for long-horizon work | **超过 30 分钟**的长程 agentic / coding，token 预算以百万计 |
| `high` | High capability. **Equivalent to not setting the parameter** | 复杂推理、困难编码、agentic 任务 |
| `medium` | Balanced approach with moderate token savings | 需要速度/成本/性能平衡的 agentic 任务 |
| `low` | Most efficient. Significant token savings with some capability reduction | 简单任务、**subagent** |

> *"Effort is a behavioral signal, not a strict token budget."* 低档不是「不思考」，是「同一个难题上思考得少」。

### A.2 Opus 5 专属建议（原文，与上表冲突时以此为准）

> **Start with `high`, the default**, and adjust based on your evals: step up to `xhigh` for demanding coding and agentic work, or to `max` when a task justifies unconstrained token spending, and **use `low` and `medium` liberally as your primary control for token cost and response time wherever your evals show quality holds**. If you carried effort settings over from an earlier model, run a fresh effort sweep on your evals rather than reusing them.

三条硬事实：

- **effort 控制的是「想多少」不是「说多少」**：*"Effort controls thinking volume, not visible response length: on Claude Opus 5, changing effort does not reliably shorten responses, so prompt for length instead."*
- **`xhigh` / `max` 下不能关思考**：`thinking: {"type": "disabled"}` 在这两档返回 400。
- **`xhigh` / `max` 要给大 `max_tokens`**：官方建议 **64k 起步**再调。
- Opus 5 **没有** "default effort hold"（Fable 5 / Opus 4.8 / 4.7 才有）——你不设它每次就是 `high`。

### A.3 Claude Code 侧（`/effort`）

来源：[Model configuration](https://code.claude.com/docs/en/model-config)

- 支持档位：Opus 5 / Sonnet 5 / Opus 4.8 / 4.7 全部五档；Opus 4.6 / Sonnet 4.6 **没有 `xhigh`**。
- 默认：**`high`（除 Opus 4.7 外的每个模型）**；Opus 4.7 默认 `xhigh`。
- **`ultrathink` ≠ 提 effort**（纠正一条广为流传的社区说法）：官方原文 *"Include `ultrathink` anywhere in your prompt to request deeper reasoning on that turn **without changing your session effort setting**. Claude Code recognizes the keyword and adds an in-context instruction. **The effort level sent to the API is unchanged.**"*
  → 我们 `~/.claude/CLAUDE.md` 写的「`ultrathink` 仍有效但只提升当前一轮」**是对的**，可以补精确：它加的是上下文指令，**不改 API 的 effort 值**，所以「设了 max 再打 ultrathink 会降档」这个 HN 上的说法（2026-04 `robeym`）**不成立**。
- **`ultracode` 是另一回事**：它不是 effort 档，是 Claude Code 的一个设置 —— 发 `xhigh` 给模型 **+** 让 Claude 对每个实质任务编排 dynamic workflow。`CLAUDE_CODE_EFFORT_LEVEL` 和 `effortLevel` **不接受** `ultracode`；且 `CLAUDE_CODE_EFFORT_LEVEL` 设成非 `xhigh` 的值时，ultracode 的编排会静默失效。
- 优先级（取第一个成立的）：`CLAUDE_CODE_EFFORT_LEVEL` / `--effort` / `/effort` → 模型默认保持（Opus 5 无） → `modelSettings` / `effortLevel` → 模型默认。

---

## B. Opus 5 的行为差异与对应指令（官方原文）

来源：[Prompting Claude Opus 5](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5)

这一页是本次调研**信息密度最高**的东西。逐条摘：

### B.1 输出更长 —— 要显式压

> *"Claude Opus 5's default user-facing responses run longer than prior Opus models'. The effort parameter controls how much the model thinks rather than how much it says... To control response length, prompt for it explicitly."*

官方给的原文指令：

```text
Keep responses focused, brief, and concise. Keep disclaimers and caveats short, and spend most of the response on the main answer. When asked to explain something, give a high-level summary unless an in-depth explanation is specifically requested.
```

长 system prompt 里还要在**结尾**再放一次短提醒：

```text
<tone_preference>
Keep outputs reasonably concise.
</tone_preference>
```

### B.2 agentic 过程中话多 —— 要规定播报节奏

> *"Claude Opus 5 narrates readily during agentic work... It benefits from explicit guidance on how to communicate with the user during a task."*

```text
Before your first tool call, say in one sentence what you're about to do. While working, give a brief update only when you find something important or change direction. When you finish, lead with the outcome: your first sentence should answer "what happened" or "what did you find," with supporting detail after it for readers who want it.
```

> 反向调也用同一个杠杆。官方补一句：**正面示例比「不要做什么」的禁令更有效**。

### B.3 写到磁盘的文档也更长

```text
Match the length of written documents to what the task needs: cover the substance, but do not pad with filler sections, redundant summaries, or boilerplate.
```

### B.4 ⚠️ 过度自验 —— 官方要求**删掉**通用自验指令

> *"Claude Opus 5 verifies its own work without being told to. **If your prompt contains explicit verification instructions ("include a final verification step for any non-trivial task," "use a subagent to verify"), remove them**: instructions like these cause over-verification on Claude Opus 5, and removing them reduces wasted tokens with no loss in quality. The same applies to legacy harness scaffolding that adds separate verification steps."*

**这条要小心读，别误伤。** 它说的是**泛化的「记得自己检查一遍」**，不是**领域特定的确定性 gate**。本仓库的真机测试纪律、`guard.mjs`、`stop-checklist.mjs` 属于后者，**不在这条的射程内** —— 官方 Claude Code 最佳实践页同时在说 *"Give Claude a check it can run"*，两者不矛盾：**删的是靠嘴说的自验，留的是能返回 pass/fail 的 gate。**

### B.5 范围扩张 —— 要显式收口

```text
Deliver what was asked, at the scope intended. Make routine judgment calls yourself, and check in only when different readings of the request would lead to materially different work. If the request seems mistaken or a better approach exists, say so in a sentence and continue with the task as asked rather than quietly narrowing, widening, or transforming it. Finish the whole task, and stop short of actions that are clearly beyond what was asked.
```

### B.6 更爱派 subagent —— prompt 阻尼 + **硬上限**

> *"Claude Opus 5 delegates to subagents more readily than prior models. Delegation pays off on genuinely independent, sizeable tracks of work, but it multiplies cost and time when applied to small tasks."*

官方阻尼指令原文：

```text
Delegate to a subagent only for large tasks that are genuinely independent and parallelizable, such as a wide multi-file investigation. Do not delegate work you can finish yourself in a handful of tool calls, and do not use subagents to verify or double-check your own work. If one subagent can complete the task, use one rather than several, and keep spawn counts low.
```

**硬上限**（[Cap subagent depth, concurrency, and spend](https://code.claude.com/docs/en/agent-sdk/subagents)）：

| 限制 | 变量 | 默认 | 到顶时 |
|---|---|---|---|
| 嵌套深度 | `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` | `3` 层（设 `1` = 禁止 subagent 再派 subagent） | 最底层 subagent 自己干 |
| 并发数 | `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` | `20` 个同时跑 | 拒绝派新的，返回 `Concurrent subagent limit reached`；**ultracode 会话不受此限** |
| 花费 | SDK 的 `maxBudgetUsd` / `max_budget_usd` | 无 | 停背景 subagent + `error_max_budget_usd` 结束 |

要求 Claude Code ≥ 2.1.219（SDK 页口径）/ ≥ 2.1.217（prompting guide 口径）。**本机 2.1.224，满足。**

> 附一条容易忽略的：用 `claude_code` system prompt preset 且模型是 Opus 5 时，Claude Code **会自己加**一句「非要求不要调 Agent 工具」；用自定义 system prompt 时**没有这句**。交互式 CLI 走的是 preset。

### B.7 自我纠错 —— 别再让它 double-check

> *"Avoid instructing re-checks it already performs ('double-check your answer,' 're-verify before responding'); like verification instructions, these compound with the model's own behavior and add cost without improving results."*

它还会**过度播报自己的更正**，官方压制指令：

```text
Only correct an earlier statement when the error would change the user's code, conclusions, or decisions. State corrections plainly and briefly, then continue the task. For slips that change nothing for the user, make the fix and move on without noting it.
```

### B.8 ⭐ code review 上的关键反直觉一条

> *"Code review and bug-finding: Claude Opus 5 reviews code with high precision and recall... **Accuracy holds at lower effort settings**, which supports a fast pass at review time and a more thorough pass later. **If your review prompt says "only report high-severity issues" or "be conservative," the model may follow that instruction literally and report less; ask it to report everything and filter in a separate pass instead.**"*

### B.9 其它

- **多文件重构 / 端到端功能是 Opus 5 最强的地方**，且 *"performs best when given the complete task specification up front and left to run"* —— 一次把完整规格给全，别挤牙膏。
- 1M 上下文是**默认也是上限**，*"instruction following, tool calling, and reasoning stay consistent throughout the window"*。
- 视觉：图表 / 文档 / 图示 / UI 复刻都强，且 *"tool use is a more cost-effective lever than thinking alone"* —— 让它**截图-裁剪-再看**，比硬提 effort 划算（对本仓库的 UI 走查直接可用）。
- 关思考时有两种伪影（工具调用被写成正文、`<thinking>` 标签泄漏）。**我们不关思考，不受影响**，但记一笔。

---

## C. 官方工作流（Claude Code 最佳实践）

来源：[Best practices for Claude Code](https://code.claude.com/docs/en/best-practices)、[Effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)

### C.1 一切最佳实践的**唯一约束**

> *"Most best practices are based on one constraint: Claude's context window fills up fast, and performance degrades as it fills."*

### C.2 给它一个能自己跑的 check（四级，按「设置成本 ↔ 省注意力」排）

| 强度 | 形式 | 停在哪 |
|---|---|---|
| 一次性 | prompt 里写「跑完 check 并迭代」 | 本轮 |
| 会话级 | `/goal <条件>` | 独立评估器每轮判，满足才收工 |
| 确定性 gate | **Stop hook** 跑脚本 | 不过不许结束（连拦 8 次后 Claude Code 强制放行） |
| 第二意见 | verification subagent / dynamic workflow | 新鲜模型试图推翻结论 |

> *"Have Claude show evidence rather than asserting success: the test output, the command it ran and what it returned, or a screenshot."*

### C.3 `/goal` 的机制（本仓库最有增量的一条）

来源：[Keep Claude working toward a goal](https://code.claude.com/docs/en/goal)

- 本质是**会话级的 prompt-based Stop hook**。每轮结束后把「条件 + 对话」发给小快模型（默认 Haiku），返回 **met / not yet met / impossible** 三种裁决。
- ⚠️ **评估器不跑命令也不读文件**，*"It doesn't run commands or read files independently, so write the condition as something Claude's own output can demonstrate."*
- 好条件的三要素：**一个可测的终态** + **说清怎么证明**（如 `npm test` exits 0）+ **不许动的边界**。上限 4000 字符。
- 可以写 `or stop after 20 turns` 来兜底。
- 连续几轮不调工具就自动停下把控制权还你。
- 有后台任务时**跳过该轮评估**；后台卡满 30 分钟触发 check-in，之后按 1h → 2h 退避。
- 非交互也能用：`claude -p "/goal ..."`。

### C.4 与本仓库已有做法一致的（不用改，确认有效）

- explore → plan → code → commit 四段；**能一句话描述完 diff 的改动直接做，别进 plan mode**（官方原文与我们全局 CLAUDE.md 的判据逐字一致）。
- 纠正超过两次就 `/clear` 重开：*"A clean session with a better prompt almost always outperforms a long session with accumulated corrections."*
- subagent 只用于「读很多文件」的调研，把探索挡在主上下文外。
- 让 Claude 先面试你再写 SPEC.md，然后**新开 session** 执行 —— 与我们的 `/spec-first` 同构。
- 长任务 harness：`init.sh` + 进度文件 + 每步 git commit + 端到端验证；把关键状态**存在上下文之外**，新 session 靠它快速回到状态。

### C.5 对抗式 review 的官方警告（与我们的规则一致）

> *"A reviewer prompted to find gaps will usually report some, even when the work is sound... Chasing every finding leads to over-engineering."*

⚠️ **但它与 §B.8 有张力**：一个说「只让报影响正确性的」，一个说「说了 be conservative 就真的少报」。**解法是两段式**，见 §E.2。

---

## D. 社区评价（HN Algolia，原始评论，非转述）

检索：`"Opus 5"` tags=comment，**1,175 条命中**，取最近 60 条中相关的 45 条；另检索 `"claude code" effort`（470 条命中）。以下引用带日期与作者，可回查。

### D.1 抱怨最集中的三点（与官方 §B 完全对得上）

| 主题 | 代表评论 |
|---|---|
| **话多 / 难读** | `atonse` 09-03：*"Opus 5 has been really tough to work with. I can't understand half of what it says, it's just so damn obscure."* · `astro1234` 09-03：*"My job has gone from coding... to solving the riddle of what Opus 5 is saying"* |
| **过度读文件 / 过度验证** | `jampa` 09-05：*"Opus 5 especially tends to over-read"* · `nl` 09-05：*"Opus 5 is around 10 times slower because it does too much verification"* |
| **一致性 / 指令遵循** | `Syntaf` 09-03：*"For every 10 tasks Opus 5 accomplishes, there's at least one task that Opus 5 does just an atrocious job of"* · `bitexploder` 09-04（模型厂内部人）：*"It just can't follow an instruction to save its life and regresses rapidly"* |

**关键判断**：前两条**官方文档已经给出对应指令**（§B.1 / §B.2 / §B.4），社区大面积抱怨的原因是**没人去读那一页**。第三条无官方对应，属于真实残留风险 → 用确定性 gate 兜，别靠 prompt。

### D.2 正面评价（同样存在，别只看抱怨）

- `caconym_` 09-03：*"I've used the recent Gemini Flash models and I've used Opus 5, and the latter makes the former look like a box of broken crayons... I will eat my hat if either one can come close to Opus 5 in actual real life 'long-horizon software engineering' tasks."*
- `chmod775` 09-04（电路板设计基准）：*"Grok and Opus 5 especially stand out for doing consistently well and rarely ever scoring under 50%"* —— 而 *"Fable 5.1 seem to have a fair chance of completely failing, despite also sometimes excelling"*。
- `throwatdem12311` 09-05：指着自家站点问「有没有类似漏洞」，Opus 5 三分钟复现了同型 exploit。

### D.3 effort 相关的社区经验

- `dwaltrip` 05-28：*"If you are using Claude code, just set effort to xhigh. This one change will probably solve 80% of the problems you have noticed."*
- `extr` 05-27：*"I would just go with xhigh as a reasonable default. **Most important thing in prompting is specifying what 'done' and 'success' looks like to you.** Ask Claude to help you come up with a well formed request and spend most of your time on that, then paste that into a brand new session."*

> ⚠️ 这两条都是 **2026-05**，即 **Opus 4.7/4.8 时代**（那时 xhigh 确实是官方推荐起点）。Opus 5 的官方起点已改回 `high`，**别照抄**。`robeym`（04-16）那套 `CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING=1` + `MAX_THINKING_TOKENS` 更是过时——Opus 5 上 `budget_tokens` 直接 400。

### D.4 多模型交叉 review 是社区共识做法

`wwind123` 09-03 的流水线：Codex(gpt-5.6-sol) 出设计 → Claude(Opus 5) + Gemini 评审到全部解决 → 便宜模型实现 → 再评审。`soricus` 09-04 的关键洞察：*"What matters I guess is not the difference in models but... the fact that the critic has a different input and doesn't have their own text that needs to be defended."*

→ **这条支持我们的做法但换了理由**：交叉 review 的价值来自「评审者没有要辩护的产出」，**不是**来自「换个厂商」。所以用 Opus 5 的 subagent 做 fresh-context review 已经拿到大部分收益；用 Fable 的增量在于**不同的训练先验**，价格与延迟要为这点增量买单。

### D.5 被否掉的方案（留档）

- ❌ **`CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING=1` + `MAX_THINKING_TOKENS`**（HN 04-07/04-16 热门配方）：Opus 5 上 `budget_tokens` 已移除、返 400；且官方明说关思考会产生「工具调用被写成正文」的静默失败。**不用。**
- ❌ **无脑 `/effort max`**：官方原文 *"prone to overthinking"*、*"may show diminishing returns"*；Opus 4.7 的表更狠：*"on some structured-output or less intelligence-sensitive tasks it can lead to overthinking"*。
- ❌ **全局禁用 subagent**（`robeym` 的 `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1`）：本仓库的定位/摘要/读日志外包是实测有效的，禁掉是净亏。改用**上限**而非**开关**。

---

## E. 对本仓库的诊断（实测 + 逐条对照）

### E.1 🔴 常驻上下文 21k token —— 最大的单点

实测（2026-09-06，`wc` 字符数 ÷ 2.5 估 token）：

| 文件 | 字符 | ≈token |
|---|---:|---:|
| `~/.claude/CLAUDE.md` | 8,068 | 3,227 |
| `~/.claude/RTK.md` | 537 | 214 |
| `~/.claude/rules/common/git-workflow.md` | 1,391 | 556 |
| `~/.claude/rules/common/core.md` | 1,440 | 576 |
| `CLAUDE.md` | 1,407 | 562 |
| **`AGENTS.md`** | **22,646** | **9,058** |
| `CONTEXT.md` | 2,844 | 1,137 |
| `memory/MEMORY.md` | 14,749 | 5,899 |
| **合计** | **53,082** | **≈21,232** |

官方判据逐字：*"For each line, ask: 'Would removing this cause Claude to make mistakes?' If not, cut it."* 以及 *"If Claude keeps doing something you don't want despite having a rule against it, the file is probably too long and the rule is getting lost."*

**但这个仓库的情况特殊，不能照搬「砍」**：`AGENTS.md` 的绝大部分是**事故复盘换来的**，砍掉就是把学费再交一遍。真正可动的是**载体**，不是内容：

- `AGENTS.md` §1 的「已归档语义认知索引」6 条 ≈ 2,600 字符 —— 每条都在记忆里有全文，**这里只需要一行指针**。同样内容存了两遍。
- `MEMORY.md` 5,899 token 里，多数条目的钩子写成了段落而不是一行。官方 memory 规范就是 `- [Title](file.md) — hook`。
- **`AGENTS.md` §5 的状态机、§6 的 SOS 红线、§8 的 iOS 硬规则**是每轮都要的，留。**§9 冻结文件、§10 工作流、§11 验证命令、§12/§13 落盘位置**只在特定时刻要 —— 官方原文：*"For domain knowledge or workflows that are only relevant sometimes, use skills instead. Claude loads them on demand without bloating every conversation."* 这个仓库**已经有 9 个项目 skill**，这套机制是现成的。

> 保守估计可把常驻压到 **12–14k**，且不丢任何一条事故教训。

### E.2 🔴 review 指令在 Opus 5 上自伤

`~/.claude/CLAUDE.md`「长任务收尾前，用新鲜上下文复核一遍」那节现在写着：

> **明确告诉它只报影响正确性或违反既定需求的**，其余当可选。

官方 Opus 5 页明确说这类措辞会让它**真的少报**（§B.8）。而官方 Claude Code 页说不过滤会导致过度工程（§C.5）。**两者都对，冲突点在「谁来过滤」**：

**建议改成两段式**（同时满足两页）：
1. 第一遍：让 reviewer **全部报出来**，每条自带严重度（CRITICAL / HIGH / MEDIUM / LOW）与 `文件:行号`。
2. 第二遍：**你（或一次独立过滤）** 只取 CRITICAL/HIGH 去修，其余归档不做。

这样召回不被压制，过度工程被第二段挡住。**本仓库还有一层现成保险**：`ponytail` 模式常驻，它天然反过度工程。

### E.3 🟡 缺「控制输出长度」的指令

全仓（全局 + 项目 + rules）**0 条**控制回复长度的指令，而 §B.1 说 Opus 5 天生更长且降 effort 无效。这是 §D.1 里社区抱怨最多的那条，而我们没设防。

建议把 §B.1 的官方原文（或其中文等价）加进 `~/.claude/CLAUDE.md` —— 注意它是**全局问题不是本项目问题**，放全局。

### E.4 ✅ effort 口径过时 —— 已由姊妹篇修好

原文写的是「`settings.json` 里**没设** `effortLevel`，实际跑默认 `high`」。**这句是错的**：
实测 `~/.claude/settings.json` 明确设着 `"effortLevel": "high"`。
错因是第一次的探测脚本只打印了 `env` / `model` / `hooks`，**没打印 `effortLevel` 这个键就下了断言** ——
「只查了一处就断言不存在」，跟记忆 `rtk-silently-truncates-long-tool-output` 是同一个形状。

结论（跑的是 `high`，且这是对的）不变，依据换成：**它是显式设的，不是默认兜底的**。

规则文本已由姊妹篇改好（`~/.claude/CLAUDE.md` 现在写着「Opus 5 的 effort 起点是 `high`，
`xhigh` 是 Opus 4.7/4.8 时代的编码起点」）。

### E.5 ✅ subagent 硬上限 —— 已由姊妹篇落地

`~/.claude/CLAUDE.md` 的「委派」节是一整套**纯 prompt 的**判定表（写得很好，三条已证伪的做法也标了）。
但 Opus 5 更爱派活，官方原文：*"Either instruction only steers Claude, so set the limits as well."*

`~/.claude/settings.json` 的 `env` 现已设：

```json
"CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH": "1",   // 禁止 subagent 再套 subagent（默认 3）
"CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS": "3"    // 并发上限（默认 20）
```

数值取自姊妹篇 §6.4，理由：`SPAWN_DEPTH=1` 是「⛔ 别委派实现」的确定性版本；
并发 3 对应「互相独立的模块并行开多个」的实际用量。

### E.6 🟢 已经做对、且被官方背书的（别动）

| 我们的做法 | 官方对应 |
|---|---|
| `guard.mjs` / `stop-checklist.mjs` / `research-log.mjs` 6 个 hook | *"hooks are deterministic and guarantee the action happens"*（vs CLAUDE.md 只是 advisory） |
| AGENTS §1「事故必须落到 hook / 测试 / Stop 钩子 / 记忆」 | 与 C.2 的四级 check 表同构，且我们的更严 |
| `/spec-first` 面试 → SPEC.md → 新 session 执行 | 官方 *"Let Claude interview you"* 逐字同款 |
| 「能一句话描述完 diff 就直接做」 | 官方 *"If you could describe the diff in one sentence, skip the plan."* 逐字同款 |
| 纠正两次就 `/clear` | 官方 *"After two failed corrections, /clear"* 逐字同款 |
| 探索外包 subagent、编辑自己干 | 官方 *"use subagents to keep research out of it"* + Opus 5 阻尼指令的 *"Do not delegate work you can finish yourself"* |
| 真机测试自己跑、日志给 subagent 读 | 与 Opus 5 阻尼指令 *"do not use subagents to verify"* 一致 |

### E.7 🟢 关于 Fable 做「框架检查」

**有依据支持继续用，但理由要换**：

- 支持：`chmod775`（HN 09-04）实测 Fable 5.1 *"a fair chance of completely failing, despite also sometimes excelling"*，方差大；而 `soricus`（09-04）指出交叉评审的价值来自「评审者没有要辩护的产出」，**不是**来自换厂商。
- 官方：Opus 5 的 review 精度召回都高，**且低 effort 也保持准确**（§B.8）——所以「快扫用 Opus 5 低 effort、细审用 Opus 5 高 effort」这条便宜路子是官方明说可行的。
- 成本：`eis`（HN 09-03）*"burned through the whole weekly quota with 3 prompts in less than a day using the new Fable 5.1"*；Fable 定价 $10/$50 是 Opus 5 的两倍。

**建议**：Fable 留给「跨前后端契约一致性」「架构方向对不对」这类**需要不同先验、且错了代价大**的判断（本仓库 §7 契约同步、§5 状态机这类）；日常 diff review 用 Opus 5 两段式（低 effort 快扫 → high 细审），别默认上 Fable。

---

## F. 本项目的 effort 建议表

判据来自 §A.2 官方口径 + 本仓库任务的实际形状（AGENTS §11「跑多大范围」已经把任务分好类了）。

> ⚠️ **本表已按姊妹篇 §3.2 的反向证据下调过一档**。初稿把「跨多文件重构」直接推到 `xhigh`，
> 但有三个独立来源指向「更高 effort 在编码上反而变差」：Anthropic system card 自己承认高 effort 下
> 模型 "make more changes than the task requires"（超范围改动被评分器判罚）；Cognition FrontierCode 1.1
> 上 Opus 5 最佳分落在 **medium**，过 high 之后下降；CodeRabbit 约 100 个真实 PR 的基准里
> xhigh 精度升（39.3% vs 35.2%）但**召回降**（55.2% vs 61.1%）、nitpick 从 23 涨到 92 条。
>
> **对本仓库尤其相关**：这里的历史事故形态是「静默漂移」和「范围扩大」，**不是「想得不够深」**。
> 抬 effort 治不了前者，反而放大后者 —— ponytail 模式常驻本身就是这个失败模式的证据。

| 任务 | 建议 effort | 理由 |
|---|---|---|
| **默认**（无特别说明） | `high` | Opus 5 官方起点；`settings.json` 已显式设为这个 |
| 机械同步：契约打勾、handoff 回写、文档补一行、守卫加一条矩阵 | `low` | 官方：low/medium *"liberally as your primary control"*；有 5 道 pre-push 门禁兜底 |
| 常规单点改动 / 跨文件但方案清楚 | `high` | 官方起点，不用动 |
| **真正难的**：状态机改动、事务与异步边界、线上事故根因、疑难真机 bug 二分 | `xhigh`（**单次抬，做完调回**） | 官方：*"demanding coding and agentic work"*。**记得配大 `max_tokens`（64k 起）** |
| 代码审查 | `medium`~`high` | 官方：审查准确度**在低 effort 下保持**；且 xhigh 的 nitpick ×4 |
| 读日志、定位、大文件摘要（走 subagent） | `low` | 官方表里 `low` 的典型用途原文就写着 subagent |
| 无障碍 / VoiceOver 走查（要看截图） | `high` + **给它工具反复截图裁剪** | 官方：视觉任务上 *"tool use is a more cost-effective lever than thinking alone"* |
| SOS / 隐私 / 认证这类红线代码 | `xhigh` + 单独跑 security-reviewer | 错误代价不对称，不是省 token 的地方 |
| **从不用** | ~~`max`~~ | 本仓库没有「不计代价」的任务；编码上有 overthink 反证 |

**两条不要做的**：

- 别把 `CLAUDE_CODE_EFFORT_LEVEL` 写死在 `settings.json` —— 它优先级最高，会**盖掉** `/effort` 和
  `--effort`，还会让 `ultracode` 静默失效（§A.3）。用 `effortLevel` 键设基线，按任务用 `/effort` 临时切。
- 别在**同一会话中途**反复改 effort —— Claude Code 走顶层 effort，它参与 prompt 渲染，
  **改它缓存前缀全失效**（保缓存的 per-message effort 是 API beta，Claude Code 用不到）。
  要换档就 `/clear` 之后再换，正好并进「任务切换必须 `/clear`」那条。

> Opus 5 **没有跨会话的 effort 保持**（Fable 5 / Opus 4.8 / 4.7 才有），所以「临时抬高」天然是临时的，
> 不用担心忘了调回来粘住下一个会话。

---

## G. 落地清单与实际执行状态（2026-09-06 收工时）

| # | 动作 | 落在哪 | 状态 |
|---|---|---|---|
| 1 | 控制输出长度（回复简洁 + 写文档长度校准） | `~/.claude/CLAUDE.md` | ⏳ **未做** —— 见下方说明 |
| 2 | review 指令改两段式（全报 + 分档 → 第二遍过滤） | `~/.claude/CLAUDE.md` | ✅ **姊妹篇已落地**（现写作「让它全报并自分 A/B 两档，我只按 A 动手」） |
| 3 | subagent 硬上限 `SPAWN_DEPTH=1` / `CONCURRENT=3` | `~/.claude/settings.json` | ✅ **姊妹篇已落地** |
| 4 | ~~加官方 subagent 阻尼 + 范围收口指令~~ | ~~`~/.claude/CLAUDE.md`~~ | ❌ **撤销** —— 见下方 |
| 5 | effort 口径从「xhigh」改成 §F 那张表 | `~/.claude/CLAUDE.md` | ✅ **姊妹篇已落地**，本报告 §F 又按其 §3.2 的反向证据下调一档 |
| 6 | `AGENTS.md` §9–§13 迁进 skill，§1 索引压成路由表 | 本仓库 | ✅ **本轮完成**（PR #109） |
| 7 | `MEMORY.md` 条目钩子压回一行 | 记忆目录 | ✅ **本轮完成**（最长 17 条，14,749→11,443 字符） |
| 8 | 真机测试用 `/goal` | 用法 | ✅ **本轮完成** —— 可用的条件写法已写进 skill `aidrun-ship-check` |

**实测收益（#6 + #7）**：常驻上下文 **53,890 字符 / ~21,556 tok → 41,099 字符 / ~16,440 tok（-23%）**。
`AGENTS.md` 22,646→12,682，`MEMORY.md` 14,749→11,443。**规则一条没动，事故教训一条没丢** ——
搬走的是理由、命令与踩坑史，每节留下规则本身加一行指针。

### #4 为什么撤销

官方那三段 prompt（范围收口 / 纠错克制 / 委派约束）**已被 Claude Code 的 `claude_code` 系统提示预设内置**。
姊妹篇 §四 在系统提示里逐段核实过，本轮复核确认：`# Delivering work` 段有
"The requested scope is the deliverable — don't quietly narrow, widen, or transform it"，
`# Corrections` 段几乎逐字相同，委派那条是 "Do not use the Agent tool, workflows, or deep-research
unless the user, a CLAUDE.md file, or a skill asks for it"。

**抄进 `CLAUDE.md` = 同一件事说两遍**，还要占正在被瘦身的预算。
⚠️ 但那句官方限定要看清：**只有用 `claude_code` 预设时才自动注入委派指令**，
自建 harness 或 Agent SDK 传 custom system prompt 时**没有**，那时才需要自己加。

### #1 为什么还没做

它是唯一确认预设里**没有**对应物的一条（conciseness 与「写到磁盘的文档别注水」两段）。
但 `~/.claude/CLAUDE.md` 与 `settings.json` 在 01:46–01:48 正被姊妹篇那轮并发修改
（本轮 01:49 实测 mtime），此刻去改就是覆盖对撞 —— 记忆 `shared-checkout-concurrent-colleague-edits`
说的正是这种情况。**留给使用者在无并发时补**，官方原文见 §B.1 / §B.3。

### #6 / #7 的回滚粒度

这批与调研报告本身（#108）分开成 #109，因为回滚粒度不同：`AGENTS.md` §1 那些是事故资产，
真要回退时不应该连报告一起退。

---

## H. 未证实 / 存疑

- **「Opus 5 比 Opus 4.8 强多少」在真实工作里的幅度**：官方给的是 Frontier-Bench「翻倍」、金融建模「平均高 9 个百分点、少 1/3 轮次与工具调用、少 60% 时间」；HN 上 `verdverm`（09-02）与 `bashtoni`（09-03）都说「感觉不比 4.8 明显好」。**两边都没有可复现的本仓库证据，按未定论对待。**
- **`CLAUDE_CODE_MAX_*` 的最低版本号有两个口径**（prompting guide 说 2.1.217，SDK 页说 2.1.219）。本机 2.1.224 都满足，没去追。
- **本文件的 token 估算用 ÷2.5 的粗系数**，中文 markdown 实际比值会偏离。要精确数字得用 `messages.count_tokens`，本次没跑。**字符数与字节数别混**：`ls -la` 给的是字节，中文 UTF-8 一个字 3 字节，本轮就差点据此报出「CLAUDE.md 翻倍」的假警报。
- **姊妹篇引用的三个 effort 反向证据本轮没有独立复核**（system card 经 Zvi 转述、Cognition FrontierCode 1.1 为二手转述、CodeRabbit 基准有原文）。§F 已按它们下调，但若要拿这些数字对外，先自己核一遍原始来源。
- **`/goal` 与本仓库 Stop 钩子的叠加行为**没实测：两者都在每轮结束后跑，`stop-checklist.mjs` 有 `stop_hook_active` 兜底、`/goal` 有连拦 8 次上限，理论上不冲突，但**没验过**。

---

## I. 来源

官方（2026-09-06 抓取）：

- [Introducing Claude Opus 5](https://www.anthropic.com/news/claude-opus-5)
- [Effort — Claude Platform Docs](https://platform.claude.com/docs/en/build-with-claude/effort)
- [Prompting Claude Opus 5](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5)
- [Best practices for Claude Code](https://code.claude.com/docs/en/best-practices)
- [Keep Claude working toward a goal (`/goal`)](https://code.claude.com/docs/en/goal)
- [Model configuration (`/effort`, ultrathink, ultracode)](https://code.claude.com/docs/en/model-config)
- [Subagents in the SDK — Cap depth, concurrency, and spend](https://code.claude.com/docs/en/agent-sdk/subagents)
- [Environment variables](https://code.claude.com/docs/en/env-vars)
- [Effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)

社区：HN Algolia API（`hn.algolia.com/api/v1/search`，免 key，返回原始评论）。查询 `"Opus 5"` tags=comment（1,175 命中）与 `"claude code" effort`（470 命中）。所有引用带作者与日期，可回查。
