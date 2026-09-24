# GitHub Spec Kit 该不该进本仓库工作流

**日期**：2026-09-21
**提问**：GitHub 官方发的 spec-kit 这个库、以及它用的那种 Skill，该不该直接加进我的工作流？
**一句话结论**：**不整体引入**。它和本仓库已在用的 OpenSpec 是同一个生态位（HN 上用过两者的人逐字说 "basically these are the same tools"），而本仓库的瓶颈从来不在「规格产出」而在**真机验证**——spec-kit 的终点是「编译过了、PR 开了」，正好停在本仓库已经栽过跟头的那条线上。
**核实方式**：GitHub API + 仓库源码原文（第一手）+ 官方文档 + HN Algolia 原始评论 + Martin Fowler 实测文章。**0% 实机安装**。

---

## 1. 事实核对：它现在是什么

| 项 | 值 | 来源 |
|---|---|---|
| 仓库 | `github/spec-kit`，MIT | GitHub API |
| 星数 / fork | **138,150** / 12,380 | API，2026-09-21 |
| 最新版本 | **v1.0.8**（2026-09-17 发布），当天仍有 push | Releases API |
| 开放 issue | 309 | API |
| 安装 | `uv tool install specify-cli --from git+…@v1.0.8`，需 Python 3.11+ | Release body 原文 |
| 支持集成 | **41 个**（catalog.json 条目数），Claude Code 是其中之一 | `integrations/catalog.json` |

工作流（三条**互相独立**的入口，不是三个必经阶段）：

- **SDD**：`/speckit.constitution` →（每个 feature）`specify` → `plan` → `tasks` → `implement` → `converge`，`implement`/`converge` 循环到报 Converged
- **Bug Fixing**：`bug-assess` / `bug-fix` / `bug-test`
- **Idea Assessment**：`assess-intake` / `research` / `define` / `shape` / `decide`

可选质量闸：`clarify`、`checklist`、`analyze`。

## 2. 「它用的那种 Skill」——准确答案

**GitHub 没有单独发布一个「Claude Code Skill」。** 是 spec-kit 的 CLI 自己把命令**生成成** Claude Code skills。第一手证据在源码（`src/specify_cli/integrations/claude/__init__.py`，逐字）：

```python
class ClaudeIntegration(SkillsIntegration):
    key = "claude"
    config = {"name": "Claude Code", "folder": ".claude/", "commands_subdir": "skills", …}
    registrar_config = {"dir": ".claude/skills", "format": "markdown",
                        "args": "$ARGUMENTS", "extension": "/SKILL.md"}
```

⇒ `specify init --integration claude` 往 `.claude/skills/<命令名>/SKILL.md` 写文件，**不是** `.claude/commands/`。

同一个文件里还有两条**对本仓库直接有用的事实**：

1. 它能往 `.claude/settings.json` 注册钩子（`events_config_file = ".claude/settings.json"`，映射 `SessionStart/PreToolUse/PostToolUse/SessionEnd/UserPromptSubmit/Stop`）。本仓库这个文件里已经挂着 7 个钩子（PreToolUse 4 / PostToolUse 1 / SessionStart 1 / Stop 1）。`events.py` 走的是 merge 不是覆写，且只在有 handler 声明时才动它——但这是**共享同一个文件**，属于必须盯的面。
2. 🔑 **它自己承认长会话会被自家命令撑爆**（源码注释逐字）：

   > `analyze` was previously forked … but in practice `/speckit-analyze` returns a **300-500 line report** that is injected back into the main conversation. In long sessions each subsequent fork inherits that growing context, **compounding overhead until the chat freezes** (#3185).

   这条直接撞上本仓库 `claude-code-token-optimization-20260917` 的结论面。

**第三方那几个不是官方**，别混淆：`jbaruch/spec-kit-skills` **已归档**（改名 Intent Integrity Kit，命令从 `/speckit-*` 改 `/iikit-*`）；`dceoy/speckit-agent-skills`、`feiskyer/claude-code-settings` 是社区包；仓库里 PR #1451（Claude Code plugin + marketplace 分发）**仍是未合的 PR，不是已发布能力**。

## 3. 为什么本仓库不该整体上

### 3.1 生态位已被 OpenSpec 占着，装了就是第二套源真相

本仓库现状（当场查的，不是推断）：`openspec/config.yaml` 写着 `schema: spec-driven`，`openspec/changes/` 下 **14 个未归档变更**，`.claude/skills/` 里有 4 个 `openspec-*` skill，另有全局 `spec-first` skill 负责「面试→SPEC.md」那一段。

spec-kit 会新开一套 `.specify/` + `specs/NNN-feature/`。`AGENTS.md` §2 定了源真相优先级链，§9 立过一条教训：**「写『以 X 为准』再抄一份 X，等于制造一个必然过期的第二源」**。两套 SDD 工具并存就是这条的放大版。

HN 上同期（2026-09 中旬，OpenSpec 那个帖子）用过两者的人的原话：

- crossroadsguy（09-17）：「I mostly use speckit, not openspec. **I think basically these are the same tools.**」
- dmos62（09-18）：「**OpenSpec is a very lightweight framework by comparison**（相对 SpecKit）」
- slowmovintarget（09-16）：「it is **definitely less heavy than SpecKit**」

⇒ 换过去是「同功能 + 更重」，不是「补了一块空白」。

### 3.2 它解决不了本仓库真正卡住的那一段

`claude-agent-view-for-cross-repo-20260919` 已经量过：14 个未归档变更 **42 条未完成**里 **≈27 条（64%）是真机人工验证**（开 VoiceOver 听回播、AX5 目视、两台设备长期离线）。spec-kit 的 `/speckit.implement` + `/speckit.converge` 收敛判据是它自己产出的 task 清单走完，**天花板就是「编译过了」**——正是记忆 `merged-prs-whose-tests-never-ran` 记的那个事故形态（本仓库 CI 跑不了任何 XCTest，绿只是编译信号）。

要「给定条件迭代到满足」，本仓库 09-21 刚调研完更省的现成解：`/goal`（`goal-command-for-device-tests-20260921.md`），条件直接写死 `failed=0 且 passed>0`。

### 3.3 评审负担与 token 代价

- 10 个命令模板合计 **135,663 字节**（最大的 `checklist.md` 22,340 / `clarify.md` 19,507 / `specify.md` 18,453）。skill 形态不进缓存前缀（按本仓库 09-17 的结论是纯赚），但**调用一次就是一整份进上下文**，`analyze` 那条自家注释已说明后果。
- Martin Fowler 网站实测（Birgitta Böckeler，**2025-10-15**，⚠️ 已近一年、spec-kit 当时还没有 `converge`/extensions，引用时必须标这条）：

  > "spec-kit created a LOT of markdown files for me to review. They were repetitive, both with each other, and with the code that already existed."
  > "I'd rather review code than all these markdown files."

- HN 原始评论同向（不是软文，是用过的人）：ctxc「generated steps that were the equivalent of Tony Stark building a robot from scratch in a cave when 'just screw this bolt on' would have sufficed」；yoaviram 两个新项目各跑十天，结束时「Most tests were failing, and the build was not successful」；loveparade（2026-09-17）「**You are just moving ambiguity and code review from one place to another without really gaining anything.**」
- 反面意见也要记：crossroadsguy 说它的价值在**纪律**（「enforce discipline for me and the LLM … Helps me save tokens as well」）。这条对「没有任何流程」的人成立，对本仓库不成立——纪律这块已经由 AGENTS.md + 6 个钩子 + OpenSpec 占了。

## 4. 值得单独取走的（不装整套也能拿）

1. **existing-projects 指南那句判据**（官方原文）：「Do not make "document the entire existing system" your first feature unless that inventory is itself the intended deliverable.」——对任何 SDD 工具都成立，免费。
2. **constitution 的概念** = 我们的 `AGENTS.md`，已有且更硬（它是可执行的钩子不是提示词）。
3. **`converge` 的「收敛而非一次性清单」思路** → 本仓库的载体是 `/goal` + Stop 钩子，不需要引它的实现。

## 5. 真要试的话，最省事、风险最低的路径

官方对既有仓库给的命令是：

```bash
specify init --here --force --integration claude
```

`--force` 的官方原文警告：「**may replace files at conflicting managed paths**, so use it only after creating a reviewable baseline. It does not delete the rest of your application.」

针对本仓库实查过的三条：

- 它写 `.claude/skills/speckit-*/SKILL.md` + `.specify/`。**名字不与现有 10 个 skill 相撞**（`aidrun-*` / `openspec-*` / `swiftui-pro`）。
- **不写 `AGENTS.md` / `CLAUDE.md`**——`src/specify_cli/integrations/base.py`（1911 行）里 `AGENTS.md` / `CLAUDE.md` / `agent_context` / `context_file` **各 0 次命中**。这条是好消息，本仓库最怕的就是这两个文件被工具改写。
- ⛔ **别在主 checkout 里试**。本仓库是共享 checkout（前后端两个工作区共用 `.git`，记忆 `shared-checkout-concurrent-colleague-edits`），`--force` + 同事在改文件 = 事故面。要试就 `git worktree add` 一个一次性目录。

## 6. 本篇的限制

- **0% 实机安装**，全部结论来自源码原文与官方文档（属「已核实文档、未验证行为」）。
- Fowler 那篇是 2025-10 的实测，spec-kit 已从那时的形态走到 v1.0.8（新增 converge / extensions / bugfix / assessment 三入口），**批评的具体形态可能已变，方向性结论（产物多、评审重）未见被推翻**。
- 没有核实 spec-kit 的 TDD 硬约束（搜索转述说「no implementation code before tests fail」）——本仓库 CI 跑不了 XCTest，若真有这条硬约束会额外冲突，**但没拿到原文，不作为论据**。

---

**来源**

- https://github.com/github/spec-kit ·  API 元数据与 releases
- `src/specify_cli/integrations/claude/__init__.py` / `base.py` / `events.py`（raw 原文）
- https://github.github.com/spec-kit/ · `docs/guides/existing-projects.md`
- https://martinfowler.com/articles/exploring-gen-ai/sdd-3-tools.html（Birgitta Böckeler，2025-10-15）
- HN Algolia 原始评论：story 45610996（2025-10-16，128 分/32 评论）、「OpenSpec – A lightweight and configurable AI spec framework」帖下 2026-09-16~20 的多条对比评论
