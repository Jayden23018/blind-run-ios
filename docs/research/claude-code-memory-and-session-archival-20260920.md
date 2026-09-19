# Claude Code 的会话归档与记忆召回：官方能力 / claude-mem / NotebookLM 连接

- 日期：2026-09-20
- 触发：用户问「能不能把 Claude Code 和 NotebookLM 连起来 + 每个 session 结束自动归档、下次按需召回，不用重复输入上下文 + claude-mem 该不该装」
- 档位：C 档（三线并行 + 本机实证）
- 本机基线：Claude Code **2.1.224**，macOS，Max 订阅，Opus 5

---

## 0. 一句话结论

**三件事分别是：已经有了、已经试过并失败了、连不上。**

1. **「会话归档 + 按需召回」你已经有四层**，其中两层是官方的、两层是你自建的。缺的不是工具，
   是**这四层各自的保质期你没量过** —— 最关键那层（transcript 全文检索）**只有 30 天**。
2. **claude-mem 不用调研该不该装 —— 这台机器上装过、跑了 111 天、产出记忆 0 条、已卸载**，
   残留 81MB。失败签名是日志里 2289 次 `SDK session poisoned`。
3. **NotebookLM 消费者版没有官方 API、没有官方 MCP**，第三方全是逆向，star 最高那个（3,432★）
   调研当天已归档停更。**而且方向是反的** —— 它进得去出不来（聊天历史零导出通道），
   而「召回」要求取得出来。要一个能沉淀又能取回的研究库，`~/Documents/Obsidian Vault`
   **已经挂在本会话的工作目录里**，零配置可读写。

**真正该做的只有一件事**：给「召回」加触发条件（§5.1）。你的问题不是没存下来，
是**存下来了没人去翻**。

---

## 1. 🔴 本机一手实证：claude-mem 已经装过并失败了（[高]，本机数据）

用户问的是「我不确定是否应该装上」。实际状态是**装过、用过、卸了**。

| 事实 | 数据 | 来源 |
|---|---|---|
| 运行期 | **2026-04-09 → 2026-07-29**（111 天），日志写到 08-03 | `claude-mem.db` `sdk_sessions.started_at` |
| 版本 | v12.4.3 | `~/.claude-mem/.cleanup-v12.4.3-applied` |
| 当前状态 | **已卸载**：`which claude-mem` = not found、`pgrep -f claude-mem` 无命中、全局 `settings.json` 不含它的 hook | 本机 |
| 残留 | **81MB**（logs 69M / chroma 8.7M / db 2M） | `du -sh ~/.claude-mem` |
| 采集量 | `sdk_sessions` **163** 条（全部 `status=completed`）、`user_prompts` **1446** 条 | SQLite |
| 🔴 **产出量** | `observations` = **0**、`session_summaries` = **0** | SQLite |
| 失败签名 | 单份日志里 **2289 次** `SDK session poisoned — killing and respawning {outputClass=prose, consecutiveInvalid…}` | `logs/claude-mem-2026-07-26.log`（82084 行：INFO 54922 / WARN 13968 / ERROR 2290） |
| 覆盖项目 | demo(52) · minecraft-ai(47) · final_project(20) · 医学影像(16) · mac(10) —— **blind-run-ios 零次** | SQLite |

### 1.1 为什么这条最值钱

`status` 全是 `completed` 而 `observations`/`session_summaries` 全是 0 —— 它**自认为成功了 163 次，
实际一条记忆都没产出**。这是本仓库记忆 `known-red-suites-hide-new-failures` 和
「零执行不是通过」的同一形状：**工具报告成功 ≠ 工具做了事**。

`SDK session poisoned {outputClass=prose}` 的含义是：它起的子会话返回了散文而不是它要的结构化输出，
于是判定「中毒」→ 杀掉重启 → 再失败 → 循环。

### 1.2 成本侧（这条决定「要不要再装一次」）

配置逐字：

```
"CLAUDE_MEM_MODEL": "claude-sonnet-4-6",
"CLAUDE_MEM_CLAUDE_AUTH_METHOD": "cli",
"CLAUDE_MEM_MAX_CONCURRENT_AGENTS": "2",
```

⇒ 它做摘要**走你自己的 Claude 订阅额度**（`cli` 认证），最多 2 个并发。
2289 次重启里每一次都是一次真实模型调用，**产出为零**。

⚠️ **不要栽赃**：用户 09-17 报的额度问题（见 `claude-code-token-optimization-20260917.md`）
发生在它停止运行（08-03）**之后 45 天**，两件事时间上不重叠，**不能说额度问题是它造成的**。

---

## 2. 你现在已经有四层记忆（[高]，本机实测）

| # | 层 | 存哪 | 现有规模 | 注入方式 | **保质期** |
|---|---|---|---|---|---|
| 1 | **auto memory**（官方） | `~/.claude/projects/<proj>/memory/` | 71 个 md + `MEMORY.md` 32.5KB | `MEMORY.md` 每会话全量注入；topic 文件按需读 | 永久（除非删） |
| 2 | **board 看板**（你自建） | `~/.claude/board/sessions/*.json` | 390 个会话（本项目 **130**），1.9MB | SessionStart 注入**最近 3 个** × 硬上限 **900 字符** | **30 天**（`PRUNE_DAYS=30`） |
| 3 | **docs/research + docs/review**（你自建） | 仓库内 markdown | research 32 篇 + INDEX 29k tok | 按需读，`research-log.mjs` 开搜前强制注入索引 | 永久（进 git） |
| 4 | **transcript 全文检索**（官方，桌面端） | `~/.claude/projects/*/*.jsonl` | 576 个 jsonl | `search_session_transcripts` 工具，我主动调 | 🔴 **30 天** |

### 2.1 第 4 层实测：能用，但有两个坑

**实测 3 次**（本会话）：

| 查询 | 结果 | 判读 |
|---|---|---|
| `MAMultiPointOverlay` | 5 条命中，snippet **逐字相同** | ❌ 噪声：命中的是 5 个会话各自读过的 `INDEX.md` 同一行 |
| `Test crashed with signal kill` | 4 条命中，**各不相同且精准**（含并发抢设备的时间戳分析） | ✅ 高质量 |
| `minecraft` | 命中 `~/claude_workspace/minecraft-ai` 的会话 | ✅ **跨项目全局检索**，返回 `cwd` 可区分 |

⇒ **判据：查询词如果出现在「每个会话都会注入的文档」里（`INDEX.md`、`AGENTS.md`、`MEMORY.md`），
检索结果会被这些文档淹没，全是噪声。** 要召回真实讨论，得用只可能出现在对话里的词
（错误签名、具体数字、临时文件名）。

### 2.2 🔴 30 天是硬墙，且**静默**

```
cleanupPeriodDays 设置: (未设置 → 官方默认 30 天)
jsonl 数: 576 | 最老: 2026-08-03 | 最新: 2026-09-20 | 30 天内: 567/576
```

实测：搜 `ITMS-91053`（08-21 那次隐私清单调研的核心词），召回的**全是 9 月的会话**——
因为它们读过 `INDEX.md`；**08-21 那次原始会话的 transcript 已经不在了**。

⇒ **transcript 不是长期记忆，是 30 天的短期缓冲。** 真正扛长期的是第 1 层和第 3 层，
因为它们是**主动落盘的产物**，不是原始流水。
这反过来证明本仓库 `AGENTS.md` §12/§13「调研和 review 必须落盘」那两条**是对的**，
而且理由比当初写下时更硬。

### 2.3 一条我差点报错的发现（留作教训）

`MEMORY.md` 是 **33277 字节 = 32.5KB**，而官方文档写着「first 200 lines, or the first 25KB,
whichever comes first」。按字节算 ⇒ 第 59~73 行（15 条记忆）应该被截断。

**但对照本会话实际注入的内容，第 59 行和最后一条（第 72 行）都在。⇒ 没有截断。**

25KB 大概率按**字符**而非 UTF-8 字节计（中文 1 字符 = 3 字节，32.5KB 字节 ≈ 11.1k 字符，
远未到 25K 字符）。**算术推断触发上限、实际观察未触发** —— 这正是记忆
`reviewer-numbers-that-match-a-red-line` 记的那类错误：撞上已知红线时最该自己量。

⚠️ 仍然成立的风险：**这个截断如果发生，是静默的**。中文内容真实容量约 75KB 字节，
现在 32.5KB，还有约 2 倍余量；但索引只增不减，到点不会有任何提示。

---

## 3. claude-mem 的上游状况：项目很健康，但这不改变 §1 的结论

仓库是 **`thedotmack/claude-mem`**（Apache-2.0）。搜索里 `y1024/` `jinzaizhichi/` `Mu-L/` 等同名
全是 fork 镜像。GitHub API 实测（2026-09-20）：

| 指标 | 值 |
|---|---|
| Star / Fork | **94,252** / 8,320 |
| 最近 push | **2026-09-19**（调研前一天，日更节奏） |
| 最新 release | v13.24.23（2026-09-11） |
| open issue / open PR | 41 / **183** |
| 贡献者 | 名义 30，**最近 10 条 commit 有 9 条是同一人** |

⇒ **不是烂尾项目。** 但 183 个 PR 堆积 + 单人 bus factor + 下面三个 issue 的形态，
说明稳定性是拿快速迭代换的。

### 3.1 三个直接对口的 issue（[高]，issue 原文）

| # | 标题 | 为什么对你重要 |
|---|---|---|
| [#2579](https://github.com/thedotmack/claude-mem/issues/2579) | 卸载器留下 `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1` | 安装时它会**关掉 Claude Code 原生 auto memory**，卸载时不还原 ⇒ 原生记忆静默失效 |
| [#3905](https://github.com/thedotmack/claude-mem/issues/3905) | 13.24.0 泄漏 808 对 `chroma-mcp` 孤儿进程、吃掉 74GB swap | 原文：`drove the host to 887 MB short of full swap exhaustion`；13.24.1 只修了触发器没堵住泄漏路径 |
| [#1848](https://github.com/thedotmack/claude-mem/issues/1848) | token consumption | 用户原话：`The moment I start the session, 40% of my tokens disappear instantly` |

🔴 **#2579 已在本机核实：`~/.claude/settings.json`、`settings.local.json`、仓库 `.claude/settings.json`、
`~/.claude.json` 四处全部不含 `CLAUDE_CODE_DISABLE_AUTO_MEMORY`** ⇒ 这条风险在这台机器上**没有命中**，
原生 auto memory 是好的（71 个记忆文件仍在更新可佐证）。

### 3.2 两条要纠正的传言

- **HN 上没有讨论。** `news.ycombinator.com/item?id=46229436` 经 HN Algolia API 核实是
  **0 评论 / 1 分的纯链接帖**。「HN 讨论热烈」是假线索。[高]
- **「不收集遥测」与自己的文档矛盾。** GitHub Security 页声明不收集，而 `docs.claude-mem.ai/telemetry`
  承认向 **PostHog** 发送模型 ID、计费档位、每会话 `observer_turn_rollup`、脱敏报错文本。
  不是「把 transcript 整段外发」，但措辞与行为有落差。[中]

### 3.3 🔑 本节最重要的一句

**94k star、日更、Apache-2.0、文档齐全 —— 所有外部信号都是绿的，而它在这台机器上跑了 111 天产出 0 条。**

这和记忆 `external-skill-may-lower-your-standard`（125,726★ 项目的高价值部分只有 117 行）、
`reviewer-numbers-that-match-a-red-line` 是同一条教训：**star 数不是证据，本机实测才是。**
调研上游是为了知道「它现在修好了没有」，不是为了推翻本机已经跑出来的结果。

### 3.4 竞品（[高]，GitHub API 2026-09-20）

| 项目 | Star | License | 机制 | 与 claude-mem 的差别 |
|---|---|---|---|---|
| [mem0](https://github.com/mem0ai/mem0) | 65,641 | Apache-2.0 | 通用 LLM 记忆层，向量+图混合 | 跨工具通用 SDK，默认更依赖云端 Platform |
| [agentmemory](https://github.com/rohitg00/agentmemory) | 28,612 | Apache-2.0 | 12 hook + 54 MCP 工具，**默认零 LLM**（BM25 + 本地 ONNX embedding） | **唯一不需要任何 API key / 不烧你额度的方案** |
| [MemPalace](https://github.com/MemPalace/mempalace) | 59,150 | MIT | SQLite + Chroma，声称 170 token 完成启动注入 | ⚠️ 有第三方审计指控刷星（同秒两颗、63 秒 10 颗），**[中]**，本轮未独立复现 |
| [MCP memory server](https://github.com/modelcontextprotocol/servers) | 90,464 | 未声明 | 官方参考实现，本地 JSON 知识图谱 | **无自动注入**，全靠模型主动调工具 |
| [claude-supermemory](https://github.com/supermemoryai/claude-supermemory) | 2,764 | **无许可证**（API 返回 null） | 依赖 Supermemory 云服务 | 非本地方案；无 license = 法律上保留所有权利 |

**全部候选均无 AGPL/SSPL 污染。** 唯一值得记住的是 **agentmemory 的「默认零 LLM」**——
它是这批里唯一不消耗你订阅额度的，而「烧额度」正是 claude-mem 在本机失败时的成本侧。

### 2.4 官方对这件事的口径（[高]，官方文档原文）

**① 你的 `memory/` 目录不是自建的，是官方 auto memory 的默认路径。**

> "Each project gets its own memory directory at `~/.claude/projects/<project>/memory/`.
> The `<project>` path is derived from the git repository, so all worktrees and subdirectories
> within the same repo share one auto memory directory."
> "The first 200 lines of `MEMORY.md`, or the first 25KB, whichever comes first, are loaded at
> the start of every conversation... Claude reads them on demand using its standard file tools."
> — [code.claude.com/docs/en/memory](https://code.claude.com/docs/en/memory)

⇒ 手工编辑是**官方预期**的用法（"Auto memory files are plain markdown you can edit or delete
at any time"），不存在「手工版 vs 自动版两套并存」，也不会双份计入。
这补上了 `claude-code-token-optimization-20260917.md` §8 的空白第 3 条。

**② 「会话结束自动归档」官方明说是让你用 hook 自己做，不是内置功能。**

> "React to session events: read the `transcript_path` field that hooks and status line commands
> receive as input. **A `SessionEnd` hook can archive the transcript when a session ends.**"
> — [code.claude.com/docs/en/sessions](https://code.claude.com/docs/en/sessions)

⇒ 你的 `board_collect.py` 就是这句话的实现，而且挂在 Stop 上比 SessionEnd 更稳（见 §5.3）。

**③ 官方 CLI 文档里没有跨会话内容检索 —— 但桌面端有，我实测过。**

subagent 查遍官方 CLI 文档得到「**未查到**」，`--resume` 的 picker 只能按会话名/项目/分支过滤。
**这个结论要订正**：`search_session_transcripts` 是 **Claude 桌面 app 的 MCP 工具**，
不在 CLI 文档覆盖范围内，§2.1 的三次实测证明它可用。两者不矛盾 —— 通道不同。

**④ transcript 保留 30 天可配。**

> "By default, Claude Code stores transcripts as JSONL at `~/.claude/projects/<project>/<session-id>.jsonl`...
> The entry format is internal to Claude Code and changes between versions, so scripts that parse
> these files directly can break on any release."
> 改保留期：`cleanupPeriodDays`

⚠️ 最后半句对本仓库有直接影响：`scripts/hooks/transcript.mjs` **就是在解析这个格式**，
官方明说它「changes between versions, can break on any release」。这是一条已存在的脆弱点。

**⑤ 官方方法论：`do the simplest thing that works`。**

> "Given the rapid pace of progress in the field, 'do the simplest thing that works' will likely
> remain our best advice for teams building agents on top of Claude."
> — [anthropic.com/engineering/effective-context-engineering-for-ai-agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)

官方**没有**明说「不要自建记忆层」（subagent 明确标注「未查到」，不猜）。
但给了分工原文：「Use CLAUDE.md files when you want to guide Claude's behavior.
Auto memory lets Claude learn from your corrections without manual effort.」
以及「If an entry is a multi-step procedure or only matters for one part of the codebase,
move it to a skill or a path-scoped rule instead.」

**⑥ skill / plugin 的注入不破坏缓存前缀**（复核 20260917 结论，仍成立）：

> "Claude Code **never invalidates the cache** for a plugin's skills, commands, agents, hooks,
> monitors, or themes." — [prompt-caching](https://code.claude.com/docs/en/prompt-caching)

**⑦ API 侧的 memory tool 与 Claude Code 的 auto memory 是两套东西。**
前者（`memory_20250818`）走 `/memories` 路径、由**你的应用代码**执行六个命令，面向自己写 agent 的人；
CLI 用户用不上。[高]

---

## 4. NotebookLM：连不上，且方向是反的

### 4.1 官方接入面

| 问题 | 答案 | 置信度 |
|---|---|---|
| 消费者版（你在用的那个）有公开 API 吗 | **没有**。官方论坛帖里只有普通用户发言，**未查到 Google 官方正式声明** | [中]（负面结论，非官方原文） |
| 企业版呢 | **有**。`google.cloud.notebooklm.v1alpha`，走 Discovery Engine 主机，**Pre-GA** | [高] |
| 企业版怎么拿 | Gemini Enterprise（原 Agentspace）采购层，**$9–45/用户/月起**，不对个人 Google 账号开放 | [高] |
| 官方 MCP server | **未查到**（Google 官方零命中） | [高] |

企业版 Audio Overview 端点的官方原文：
> "This feature is subject to the 'Pre-GA Offerings Terms'... Pre-GA features are available
> 'as is' and might have limited support."
> — [docs.cloud.google.com/gemini/enterprise/notebooklm-enterprise/docs/api-audio-overview](https://docs.cloud.google.com/gemini/enterprise/notebooklm-enterprise/docs/api-audio-overview)

### 4.2 第三方 MCP 全是逆向，且头部那个刚死

| 仓库 | Star | 最近 commit | 实现 |
|---|---|---|---|
| [PleasePrompto/notebooklm-mcp](https://github.com/PleasePrompto/notebooklm-mcp) | **3,432** | 2026-09-10 | Chrome + Patchright 隐身指纹自动化。🔴 **README 首行：「This project is no longer maintained. As of September 2026 the repository is archived」** |
| [roomi-fields/notebooklm-mcp](https://github.com/roomi-fields/notebooklm-mcp) | 179 | 2026-09-04 | 逆向未公开的 `batchexecute` RPC。作者原话：「They are undocumented, so they can change **without notice**」，并建议「use a dedicated Google account for automation」 |
| 其余 3 个 | 54 / 19 / 2 | — | 同类浏览器自动化，规模更小 |

⇒ **star 最高的方案在调研当天已归档**；第二名自己建议你用小号 —— 维护者本人都承认这是灰色地带。
**没有一个第三方 MCP 基于官方 API**，因为个人层根本拿不到凭证。

### 4.3 🔴 就算连上了，方向也是反的

NotebookLM **进得去、出不来**：

- 摄入：支持 Docs/Sheets/Slides、本地文件、URL、粘贴文本、YouTube。
  自动同步**只对 Google Workspace 原生文件**（2026-05-26 上线），PDF / URL / 粘贴文本**不刷新**；
  **没有「整个 Drive 文件夹自动同步」**。
- 导出：**只能导到 Google Docs/Sheets + 音频下载 WAV**。没有整份 notebook 的导出包，
  **引用 chip 复制粘贴会丢**，**聊天历史无任何官方或第三方导出通道**。

而你的诉求是**召回** —— 召回要求「取得出来」。
⇒ **NotebookLM 的产品形态（把资料喂进去、在里面问）与「给 Claude Code 当可检索记忆」是相反的方向。**
它不是没连上，是连上了也不解决这个问题。

附：NotebookLM 不在中国大陆官方支持地区，直连跳 `?location=unsupported`。

### 4.4 替代品，以及一个你已经有的答案

| 候选 | 官方 MCP | 双向读写 | 本地优先 | 本机现状 |
|---|---|---|---|---|
| **Obsidian** | 无第一方，但社区标准 [obsidian-local-rest-api](https://github.com/coddingtonbear/obsidian-local-rest-api) **v5.0 起内置 MCP**（`127.0.0.1:27124/mcp/`，HTTPS + 自签证书） | ✅ | ✅ | vault 在 `~/Documents/Obsidian Vault`，实测 `community-plugins.json` **未装该插件** |
| **Notion** | ✅ [makenotion/notion-mcp-server](https://github.com/makenotion/notion-mcp-server) 官方 | ✅（18 工具，block 级编辑/webhook 不暴露） | ❌ 云端 | 本会话 MCP **未授权**，需交互式 OAuth（不适合无人值守） |
| Zotero | ❌ 全是社区实现 | ✅（Zotero 10+ 本地 API） | ✅ | 未装 |
| Readwise | ✅ [官方托管 MCP](https://docs.readwise.io/tools/mcp) | ✅ | ❌ | 未用 |

🔑 **但最省的答案不在这张表里**：`/Users/mac/Documents/Obsidian Vault` **已经挂在本会话的
additional working directories 里** —— 我现在就能直接 Read/Write 它，
**不需要插件、不需要 MCP、不需要 API key、不需要 Obsidian 保持运行**。

⇒ 要「一个能沉淀又能取回的研究库」，你已经有了，而且是这批候选里唯一零配置的。

---

## 5. 建议：你缺的不是存储，是**召回的触发条件**

### 5.1 判断的依据

把 §2 的表竖起来看：你已经有 **4 层归档、每层都在正常工作**：

- auto memory 71 条，每会话注入索引 ✅
- board 130 个会话卡片，每会话注入最近 3 个 ✅
- `docs/research/` 32 篇 + `docs/review/` 6 篇，进 git 永久 ✅
- transcript 全文检索，跨项目可用 ✅

⇒ **「自动归档」这件事你三个月前就做完了**，claude-mem 想解决的问题在这台机器上已经不存在。

那为什么还觉得要重复输入上下文？因为**召回是被动的**：
第 1/2 层靠「索引恰好注入了那一条」，第 3/4 层靠**我恰好想起来去搜**。
没有任何机制在「用户说『上次那个』」时逼我去查。

**所以该加的是一行规则，不是一层存储。**

### 5.2 具体动作（按性价比排序）

| # | 动作 | 成本 | 理由 |
|---|---|---|---|
| **1** | **`AGENTS.md` 加一条召回触发**：听到「上次 / 之前 / 我们讨论过 / 那个报错」先调 `search_session_transcripts`，**用只可能出现在对话里的词**（错误签名、具体数字、命令名），不要用出现在 `INDEX.md`/`AGENTS.md` 里的词 | 3 行 | 唯一真正的缺口（§5.1）。§2.1 的两次实测就是这条规则的判据来源 |
| **2** | **不装 claude-mem**，也不装竞品 | 0 | §1 本机已证伪；§3.3 star 数不是证据 |
| **3** | 清 `~/.claude-mem`（81MB，其中 69M 是失败日志） | 1 条命令 | 纯残留。⚠️ 先确认不需要 `user_prompts` 里那 1446 条历史提问 |
| **4** | **不改 `cleanupPeriodDays`** | 0 | 见下方「已否决」 |
| **5** | **不接 NotebookLM。** 要外部研究库就用**已经挂在工作目录里的 Obsidian vault** | 0 | §4.3 它进得去出不来，方向与「召回」相反；§4.4 vault 零配置可读写 |
| **6** | 给 codegraph hook 加分流判据（§6） | 中 | 是全局配置、影响另外 4 个项目，**由你自己决定**，我不替你改 |

### 5.3 已否决（留档，理由比结论重要）

| 方案 | 否决理由 |
|---|---|
| **把 `cleanupPeriodDays` 调大留住 transcript** | 治不了病还会加重：§2.1 实测已经证明**检索的噪声来自常驻注入的大文档**，留更多流水只会让噪声更多。真正该长期留的东西应该**主动落盘**成 research/review/memory —— 那正是 `AGENTS.md` §12/§13 已经在做的事 |
| **再装一层记忆工具（claude-mem / mem0 / agentmemory）** | §5.1，第五层解决不了「前四层没人触发」的问题。而且它们都要接管同一批 hook 挂载点，与现有 6 个自研 hook 抢 SessionStart/Stop |
| **把 board 从 Stop 改挂 SessionEnd**（官方文档点名 `SessionEnd` 可归档 transcript） | **现在挂 Stop 是更稳的**：会话被强杀时数据已经落盘，而 `SessionEnd` 只有约 1.5 秒预算 [中]。不要为了「更官方」把一个能用的东西改脆 |
| 用 API 侧 memory tool（`memory_20250818`） | 那是给自己写 agent 的人用的客户端工具，与 Claude Code 的 auto memory 是两套实现，CLI 用户用不上 [高] |

---

## 6. 顺带发现：一个**本会话正在发生**的 token 浪费（[高]，本机实测）

用户的诉求里有「不要反复浪费 token」。查的过程中量到一个当场成立的：

```
本会话 tool-results/hook-* 分类统计：
  codegraph 注入   : 3 次, 55.3KB ≈ 14.2k tok
  research-log 索引: 1 次, 23.0KB ≈  5.9k tok
  合计 ≈ 20.0k tok
```

`codegraph prompt-hook` 挂在 **UserPromptSubmit** 上（全局 `settings.json`），对每条用户消息
做一次代码图检索并注入 15–19KB。本会话是**纯调研会话，一行代码都没改**，而三次注入的内容是
`InMemoryTokenStore` / `LiveEscortSessionCoordinator` / `BlindRunCountdown` / `EmergencyCoordinator`
—— 与「NotebookLM 怎么连」「claude-mem 该不该装」零相关。

🔴 **更糟的是触发点**：三次里有两次是 **subagent 回来的 task-notification** 触发的。
那不是用户提问，只是一条后台完成通知，照样注入了 19KB 的 iOS 业务代码。

⚠️ **不要据此关掉 codegraph** —— 对代码任务它是净赚（`AGENTS.md` §10.6 实测 `node` 比整读省 32×）。
这是**分流缺陷**不是工具缺陷：它缺一个「这条消息像不像代码问题」的判据，以及
「task-notification 不是 user prompt」的过滤。与 `claude-code-token-optimization-20260917.md` §6
记的 `research-log.mjs` 重复注入是同一形状（钩子无条件注入，不判「这次要不要」）。

---

## 7. 共识 vs 争议

### 共识（官方与社区一致）

- 记忆要**分层 + 按需加载**，不要把一切堆进常驻上下文（官方 progressive disclosure；
  claude-mem 的 search→get_observations 两段式；MemPalace 的「170 token 启动注入」都是同一思路）[高]
- `MEMORY.md` 这类索引**每会话注入**、topic 文件**按需读**是正确形态 [高]
- 原始 transcript **不适合当长期记忆**，要落盘成结构化产物 [高]

### 争议：AI 该不该自己决定记什么

**这是本轮唯一的真争议，而且直接影响你要不要再加一层。**

- **官方立场**：自动记忆是方向。原文「Claude now automatically saves relevant memories」，
  并明说「Claude doesn't save something every session. It decides what's worth remembering」[高]
- **反对方（HN 实名用户，针对官方 auto memory 而非 claude-mem）**：
  > "I specifically disabled claude memory in a project because it kept writing down things to
  > memory that didn't need to be in memory, **including severely wrong statements that then
  > would confuse it later.**" — Fabricio20 [高，原文]
  > "It inevitably ends up dragging in things that are unrelated and unimportant to the current
  > task." — crooked-v [高，原文]

⚠️ **引用时注意对象**：这两条批的是 **Anthropic 官方 auto memory**，不是 claude-mem 插件。
但机制相通 —— 都是 AI 自主判断「什么值得记」。

**对本仓库的含义**：你的 71 条记忆是**人工审过、带出处和反例**的
（对照 `MEMORY.md` 里每条都有「判据 / 已否决 / 文件:行号」），质量明显高于自动生成。
争议的存在说明**「让 AI 自动多记一点」不是无风险的改进**，这是否决第 5 层的另一条理由。

---

## 8. 反对意见（什么情况下上面的建议是错的）

**① 如果你真正的痛点是「跨项目」而不是「跨会话」，我的结论要反过来。**
§5 全部围绕单仓库，而四层里三层是**按 repo 隔离**的：auto memory 官方原文
「The `<project>` path is **derived from the git repository**」，board 按 repo 分卡，
`docs/research/` 在仓库内。唯一跨项目的是 transcript 检索（§2.1 搜 `minecraft` 那次），
**而它只有 30 天**。如果你想要的是「在 minecraft-ai 里想起 blind-run-ios 学到的东西」，
那确实存在缺口 —— 而 claude-mem 的 db 里 5 个项目混存，那正是它的卖点。
**判据：你重复输入的上下文，是同一个项目里的，还是跨项目的？** 这一句能翻转整节结论。

**② §1 严格说只证伪了 v12.4.3，不是证伪了 claude-mem。**
本机跑的是 2026-07 之前的 v12.4.3，现在已是 v13.24.23（中间 20+ 个 minor，日更节奏）。
`SDK session poisoned` 很可能早修了。我的措辞是「这台机器上跑过并失败」，
**不是「这个项目做不到」**。要推翻它成本很低且判据现成：重装跑一周，
查 `sqlite3 ~/.claude-mem/claude-mem.db "select count(*) from observations"` 有没有非零行。
**别把「本机实测」升格成「普遍结论」** —— 那正是本报告 §3.3 批评的那种推理。

**③ 第 1 条建议（加召回触发规则）可能把噪声变多而不是变少。**
§2.1 已经证明检索会被常驻大文档淹没。如果规则写成「听到『上次』就搜」，
我会在每次听到这个词时搜回一堆 `INDEX.md` 的回声 —— 比不搜更费 token。
**规则的价值全在「用什么词搜」那半句上**，只写「记得搜」等于没写。

**④ NotebookLM 那条在一种情况下反转**：如果你所在组织买了 Gemini Enterprise，
官方 API 就存在（虽然 Pre-GA），§4.2 的逆向方案全部不必要。个人账号下不成立。

---

## 9. 来源

### 官方（[高]）
- [Claude Code — Memory](https://code.claude.com/docs/en/memory)（§2.4 ①⑤、§8①）
- [Claude Code — Sessions](https://code.claude.com/docs/en/sessions)（§2.4 ②④）
- [Claude Code — Prompt caching](https://code.claude.com/docs/en/prompt-caching)（§2.4 ⑥）
- [Claude Code — Hooks](https://code.claude.com/docs/en/hooks)（SessionEnd 等 32 个 hook 事件）
- [Claude Code — Costs](https://code.claude.com/docs/en/costs)
- [Anthropic — Effective context engineering for AI agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)（§2.4 ⑤）
- [Anthropic — Memory tool](https://platform.claude.com/docs/en/agents-and-tools/tool-use/memory-tool)（§2.4 ⑦）
- [Gemini Notebook Enterprise — Notebooks API](https://docs.cloud.google.com/gemini/enterprise/notebooklm-enterprise/docs/api-notebooks)（§4.1）
- [Gemini Notebook Enterprise — Audio Overview API](https://docs.cloud.google.com/gemini/enterprise/notebooklm-enterprise/docs/api-audio-overview)（§4.1 Pre-GA 原文）
- [Google Workspace — NotebookLM Drive 自动同步](https://workspaceupdates.googleblog.com/2026/05/keep-your-sources-up-to-date-with-automatic-Drive-syncing-in-NotebookLM.html)（§4.3）

### GitHub 硬指标（[高]，2026-09-20 API 采集）
- [thedotmack/claude-mem](https://github.com/thedotmack/claude-mem) · [#2579](https://github.com/thedotmack/claude-mem/issues/2579) · [#3905](https://github.com/thedotmack/claude-mem/issues/3905) · [#1848](https://github.com/thedotmack/claude-mem/issues/1848)
- [mem0ai/mem0](https://github.com/mem0ai/mem0) · [rohitg00/agentmemory](https://github.com/rohitg00/agentmemory) · [MemPalace/mempalace](https://github.com/MemPalace/mempalace) · [modelcontextprotocol/servers](https://github.com/modelcontextprotocol/servers) · [supermemoryai/claude-supermemory](https://github.com/supermemoryai/claude-supermemory)
- [PleasePrompto/notebooklm-mcp](https://github.com/PleasePrompto/notebooklm-mcp)（已归档）· [roomi-fields/notebooklm-mcp](https://github.com/roomi-fields/notebooklm-mcp)
- [coddingtonbear/obsidian-local-rest-api](https://github.com/coddingtonbear/obsidian-local-rest-api) · [makenotion/notion-mcp-server](https://github.com/makenotion/notion-mcp-server) · [54yyyu/zotero-mcp](https://github.com/54yyyu/zotero-mcp) · [Readwise MCP](https://docs.readwise.io/tools/mcp)

### 本机一手（[高]，不可外链）
- `~/.claude-mem/claude-mem.db`（SQLite 计数）· `~/.claude-mem/logs/claude-mem-2026-07-26.log`（ERROR 签名统计）· `~/.claude-mem/settings.json`
- `~/.claude/board/sessions/*.json`（390 个）· `~/.claude/hooks/board_{collect,inject,ask}.py`
- `~/.claude/projects/*/memory/MEMORY.md`（32.5KB）· `~/.claude/projects/*/*.jsonl`（576 个）
- `search_session_transcripts` 三次实测（§2.1）
- `/Users/mac/Documents/Obsidian Vault/.obsidian/community-plugins.json`（未装 local-rest-api）

### 已排除的假线索
- `news.ycombinator.com/item?id=46229436` —— 经 HN Algolia API 核实是 **0 评论 / 1 分的纯链接帖**，
  「claude-mem 在 HN 讨论热烈」不成立 [高]
- MemPalace 的 59,150 star 有[第三方刷星审计](https://gist.github.com/roman-rr/0569fc487cc620f54a70c90ab50d32e3)
  指控（同秒两颗星、63 秒 10 颗），本轮**未独立复现**，[中]

### 未查到（明确列出，不猜）
- Google 官方对「消费者版 NotebookLM 有没有 API」的**正式声明原文**（只有论坛用户发言）
- NotebookLM 条款里逐字的「禁止自动化」条款 —— **查不到 ≠ 被允许**
- NotebookLM 上传内容是否用于训练/人工审阅的逐字条款
- claude-mem 自动注入环节的**聚合 token 开销**官方数据（只有 issue #1848 的用户自述）
- claude-mem 的 Chroma 向量化是否调用外部 embedding API（本地 vs 云端未明确）



