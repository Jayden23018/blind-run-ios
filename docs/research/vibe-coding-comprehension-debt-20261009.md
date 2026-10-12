# AI 写代码之后，负责人怎么补回「讲得清自己的项目」

> 2026-10-09 · 触发：负责人次日要与懂技术的人讨论项目，自述对架构细节、改动历史、决策原因有「知识缺口」。
> 本报告只管**方法对不对**；按方法产出的项目材料不进本仓库（本仓库公开，材料含「谁拍板」的内部判断）。
>
> 与既有调研的关系：后端仓库 `docs/research/codebase-comprehension-for-defense-20260919.md` 做过同题的上一轮
> （工具生态 / 程序理解方法论 / 后端资产盘点）。**它的结论本轮全部沿用，不重搜**；本轮只补它没覆盖的四段：
> 理解债的新近说法、事后补写决策记录、讲项目时怎么交代 AI 的参与、「AI 当考官」有没有证据。

## 结论先行

1. **思路方向对，但「读材料」本身几乎没用，必须加「先讲再对答案」。** Anthropic 的随机对照实验（52 人）显示，
   只让 AI 生成代码的人掌握度最低；用 AI 追问概念的人掌握度明显更高。学习科学的综述把「重读」评为低效、
   「练习测试」评为高效。⇒ 材料只是题库的答案页，不是终点。
2. **事后补写决策记录（retroactive ADR）是被正式认可的做法**，但每条必须标「事后重建」、写出依据、写出置信度、
   写出缺了什么。不许让 AI 把「看起来合理的理由」补进空白处。
3. **本项目的特殊处：决策记录其实已经很多**（34 份 OpenSpec `design.md`、两份 `DECISIONS*.md`、AGENTS.md 里
   十几处「改口径」、49 份调研、后端两份面谈材料）。缺的是**「谁拍板」这一列**和**一份给人看的总图**，
   不是另一套记录系统。
4. **证据有硬断层**：本机 Claude Code 对话记录最早只到 2026-07-24（后端）/ 07-29（iOS）；iOS 仓库自 05-18 起、
   后端自 04-10 起。⇒ 7 月底之前的「为什么」只能从 git 与文档还原，材料里必须标明。
   本机 `cleanupPeriodDays` 未设，默认 30 天清理 ⇒ 当晚已把原始记录打包备份到仓库外。

## 一、理解债：问题有名字，也有补法

| 要点 | 来源 | 核实 |
|---|---|---|
| 「认知债」：AI 让人走得快，欠下的债在开发者脑子里——代码也许好懂，但人已「lost the plot」，说不清意图和实现的关系 | Willison 转引 Storey，[simonwillison.net 2026-02-15](https://simonwillison.net/2026/Feb/15/cognitive-debt/) | 主会话打开原文核对 |
| Storey 带的学生团队第 7–8 周卡死，根因不是代码乱，而是 "no one on the team could explain why certain design decisions had been made" | 同上 | 主会话核对 |
| Willison 本人："I no longer have a firm mental model of what they can do and how they work" | 同上 | 主会话核对 |
| Anthropic RCT：AI 组测验均分 50%，手写组 67%（Cohen's d=0.738，p=0.01），差距最大在调试题；"How someone used AI influenced how much information they retained" | [anthropic.com/research/AI-assistance-coding-skills](https://www.anthropic.com/research/AI-assistance-coding-skills) | 主会话核对；样本 52 人、任务约 1 小时、聊天侧栏而非自主代理 |
| Osmani 用 comprehension debt 指「代码量与真正有人理解的量之间的差距」，并明确说测试和 spec 都替代不了理解 | [O'Reilly Radar](https://www.oreilly.com/radar/comprehension-debt-the-hidden-cost-of-ai-generated-code/) | 仅 subagent 读过 |

## 二、从记录回溯决策

- 「为什么」多半在 PR 描述与讨论里，不在 commit message 里；squash 合并会压平中间过程。（subagent 归纳，非单一来源原话）
- 读 Claude Code jsonl 的现成工具 [claude-code-log](https://github.com/daaain/claude-code-log) 只负责把记录转成可读 HTML/Markdown，
  **不提炼决策**。本轮没用它：只需要「人类输入框里的话 + AI 上一段末尾」，一个几十行的脚本按 `origin.kind == "human"` 过滤即可，
  比通读导出的 HTML 省一个数量级（iOS 261 个会话 → 978 条人类消息）。
- LLM 复述历史会出错（subagent 报告 arXiv 2609.29744 称约 1/4–1/5 的回答含事实错误，**未经主会话核对**）
  ⇒ 每条结论附提交号 / PR 号 / 会话号，能回查。

## 三、ADR 与事后补写

- 原始格式（Nygard 2011）：Title / Context / Decision / Status / Consequences，动机是让后人既不「盲目接受」也不「盲目推翻」。
  [cognitect.com](https://www.cognitect.com/blog/2011/11/15/documenting-architecture-decisions)（subagent 读过）
- 微软 Azure 架构指南原文：老系统 "if the data is available, it should be retroactively generated based on known past decisions"；
  记录是 append-only，"Don't go back and edit accepted records"；**建议记录决策的置信度**（"Record the confidence level of the decision"）。
  [learn.microsoft.com](https://learn.microsoft.com/en-us/azure/well-architected/architect-role/architecture-decision-record) —— 主会话核对。
- 事后补写要 "be explicit about what details or contexts are missing"。[NimblePros](https://blog.nimblepros.com/blogs/creating-architecture-decision-records/)（subagent 读过）
- 让 AI 在开发中自动记决策：社区做法是 CLAUDE.md 规则 + skill + hook；**只写在 CLAUDE.md 里的「请记录」容易被跳过**（个人博客观点，
  与本仓库 AGENTS.md §1「文档挡不住重复犯错，要落成钩子」的既有经验同向）。

## 四、讲项目时怎么讲

- "walk me through your project" 的重点在追问：为什么选 A 不选 B、取舍现在还认不认、哪些是你做的。
  考察维度 "ownership, architectural judgment, and depth of understanding"。
  [ai-engineering-field-guide](https://github.com/alexeygrigorev/ai-engineering-field-guide/blob/main/interview/questions/03-project-deep-dive.md)（subagent 读过）
- 交代 AI 参与：具体说哪些自己定、哪些 AI 生成、AI 错在哪、你怎么发现。（多个博客的共识，只读过摘要，证据弱）
- 后端 09-19 报告已给出：被问最多的是「意图与原理」类问题（LaToza & Myers 2010，Crossref 核实过）——
  恰好是负责人「定方向」的那部分，是他的强项而不是弱项。

## 五、「先讲再对答案」与 AI 当考官

- 练习测试与分散练习被评为高效，重读与划线被评为低效。Dunlosky 等 2013，
  [psychologicalscience.org](https://www.psychologicalscience.org/publications/journals/pspi/learning-techniques.html)（subagent 读过）
- 「费曼法」本身几乎没有直接研究，证据落在自我解释 / 检索练习这些机制上；网上「提升 89%」之类数字来自商业博客，不可信。
- 「AI 当考官」只有小样本可行性试点，**没有对照实验证明它提升学习**。只当提问工具用，有效性来自检索练习本身。

## 被否掉的做法

| 做法 | 为什么不用 |
|---|---|
| 让 AI 一次性总结全部历史，直接采信 | AI 复述会错；改为每条带证据编号 + 置信度，归属判不了就写「不确定」 |
| 只出一份精读材料让负责人看 | 重读低效；材料 + 题库 + 考官 prompt 三件套 |
| 再起一套 ADR 目录 | 仓库已有 OpenSpec `design.md` / `DECISIONS*.md` / 调研索引三套；再加一套 = 第四个会漂移的源。改为在既有流程上补「谁拍板」字段 |
| 装 Understand-Anything / DeepWiki 之类代码理解工具 | 后端 09-19 报告已否（与 CodeGraph 重复 / 私有仓库要上传云端） |
| 把面谈材料放进本仓库 | 本仓库是 PUBLIC，材料含「谁拍板、哪里不懂」的内部判断 ⇒ 放仓库外 |
