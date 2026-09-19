# Claude Code 用量优化：官方机制与社区解法

- 日期：2026-09-17
- 触发：Max 计划 + Opus 5，改两个 SwiftUI 界面用掉 5 小时额度 30%+
- 本机基线：`/context` 实测 140.3k 已用，其中常驻（非对话）**约 88k**
- ⚠️ 本轮**全部经 WebSearch/WebFetch 转述 + 官方文档原文抓取**，未抓社区原文；标注置信度

---

## 0. 一句话结论

**「常驻上下文 × 每一轮」这个成本模型是错的。** 官方 prompt caching 文档逐字：
cache read「billed at roughly 10% of the standard input rate」。常驻内容是
**全价一次 + 每轮一成**，不是全价每轮。真正贵的是**缓存失效**——一次失效 =
把整个会话按全价重读一遍。所以优化的第一目标不是「删 CLAUDE.md」，
而是**别让前缀变**。

---

## 1. 缓存分层与失效（官方，[高]）

来源：[code.claude.com/docs/en/prompt-caching](https://code.claude.com/docs/en/prompt-caching)（本轮抓取原文）

三层，越靠前越少变：

| 层 | 内容 | 什么时候变 |
|---|---|---|
| System prompt | 核心指令、**工具定义** | 已加载的工具定义集合变化 |
| Project context | CLAUDE.md、auto memory、unscoped rules | 会话开始、`/clear`、`/compact` |
| Conversation | 消息、工具结果、**文件读取** | 每轮 |

原文关键句：

> "The match is exact, so a change anywhere in the prefix recomputes everything after it.
> There is no per-file or per-segment caching."

> "A change to the system prompt invalidates everything, because all later content
> now sits behind a different prefix."

### 1.1 会失效的动作（官方完整清单）

1. 切模型（每个模型独立缓存）
2. **改 effort level**（多数模型每档独立缓存；Fable 5.1 + 订阅例外）
3. 打开 fast mode（请求头进缓存键）
4. **连接/断开 MCP server**——见 §1.2，有条件
5. 启用/禁用**提供 MCP server 的** plugin
6. **整工具 deny**（如 `"Bash"` 裸名）——仅在 tool search 关闭时
7. `/compact`（对话层必然失效）
8. **图片累积到上限被批量丢弃**——丢弃改写了历史消息 ⇒ 从最早那条起重算
9. 升级 Claude Code

### 1.2 🔴 社区最热门的那个修法是反的

社区诊断页（[yurukusa cc-safe-setup](https://yurukusa.github.io/cc-safe-setup/token-consumption-diagnosis.html)，[中]）
把「Deferred Tool Loading 打断缓存前缀」列为**头号原因**，建议
`ENABLE_TOOL_SEARCH=false`。其症状描述与本例高度吻合（"session hitting 100% in under 70 minutes"），
**但机制是反的**。官方文档 §"Connecting or disconnecting an MCP server" 逐字：

> - **Deferred tools**, the default on supported models: a server connecting, disconnecting,
>   or changing its tool list **only appends new content and doesn't disturb anything already cached.**
> - **Tools loaded into the prefix**: any change to them invalidates the cache.

并且指出这类失效**不需要用户做任何事**就会发生：

> "a stdio server's process exits, an HTTP session expires, or a server reconnects
> automatically after a transient failure."

⇒ **deferral 是在保护缓存，不是在破坏它。关掉 tool search 等于把 298k 工具定义
搬回前缀，然后让每次 server 抖动都炸掉整个会话缓存。**

社区那条的真实出处应是 [#30920](https://github.com/anthropics/claude-code/issues/30920) /
[#30989](https://github.com/anthropics/claude-code/issues/30989)：2.1.69 有个
`defer_loading=true` 与 `cache_control` 同时设置导致 **400 硬错误**的 bug，
当时的 workaround 才是 `ENABLE_TOOL_SEARCH=false`。**那是修一个已修复的崩溃，
不是省 token**；被转述成通用省钱建议。

⚠️ 未验证：本机 Claude Code 版本是否已过 2.1.69。没撞过 400 就说明不适用。

### 1.3 仍然成立的 deferral 缺口

[#40314](https://github.com/anthropics/claude-code/issues/40314)（[中]，社区报告）：
HTTP / Streamable HTTP 传输的 MCP 工具**不被 defer**，stdio 的才被 defer。
报告的影响是「~120K tokens wasted per session」。
判据是 `/context` 里 MCP tools 那一行的数值——本机是 **14.5k 在前缀 / 297.9k 已 defer**，
说明 deferral 在本机**基本生效**，这条缺口不是本例主因。

---

## 2. 官方对 CLAUDE.md 的口径（[高]）

来源：[claude.com/blog/using-claude-md-files](https://claude.com/blog/using-claude-md-files)、
[the-new-rules-of-context-engineering-for-claude-5-generation-models](https://claude.com/blog/the-new-rules-of-context-engineering-for-claude-5-generation-models)

### 2.1 成本没有想象中大，但仍要瘦

> "Claude Code applies prompt caching to CLAUDE.md: the first request pays full
> input-token price, subsequent requests within roughly five minutes hit the cache
> at a much lower rate. So a sizeable CLAUDE.md costs full tokens **once per session
> rather than once per message**."

⇒ 常驻 48k 的 memory files，真实成本是「每会话一次全价 48k + 每轮 ~4.8k 等效」，
不是「每轮 48k」。仍然值得瘦，但理由从**省钱**换成**省上下文窗口 + 信噪比**。

### 2.2 Anthropic 自己砍掉了 80%

> "Anthropic removed **over 80% of Claude Code's system prompt** for models like
> Claude Opus 5 and Claude Fable 5 **with no measurable loss on our coding evaluations.**"

这是本轮最硬的一条方向性证据：官方对 Opus 5 的判断是**更少的常驻指令不降低编码表现**。

### 2.3 progressive disclosure 是现在的标准做法

> "Keep your CLAUDE.md lightweight and briefly describe what your repo is for,
> but spend most of the tokens on **gotchas inside of the codebase**."

> "Use progressive disclosure heavily, for example if you have several unique
> instructions on how to verify your work, **create a verification skill and
> reference it from your CLAUDE.md**."

> 常见误区逐字点名："A common myth is that CLAUDE.md should be a central repository
> for every practice; instead, consider a tree of files loaded at the right time."

⇒ **本仓库 `AGENTS.md` 639 行 / 23.7k 正是被点名的那个反面模式。**
它的 §0 已经有 skill 表（按需加载），但 §1.4 事故索引、§5 状态机全文、§6 SOS 红线
的长篇订正块仍是常驻的。

⚠️ 但注意：skill 的加载**不进前缀**——官方文档 §"Invoking skills and commands" 逐字
「inject their instructions as user messages at the point of invocation. Nothing
earlier in the conversation changes」⇒ **搬进 skill 是纯赚**：不失效缓存，
用到才付钱。

### 2.4 一条和本仓库习惯冲突的官方口径

> "The old advice to save things to memory via the `#` hotkey has also changed:
> Claude now automatically saves relevant memories."

本机 `MEMORY.md` 12.1k / 64 个记忆文件，是手工维护的索引。官方方向是自动记忆。
**未验证**：auto-memory 与手工 `memory/` 目录能否共存、会不会双份计入。

---

## 3. subagent 的缓存 TTL 陷阱（官方，[高]）

> "Subagents fall outside the main-conversation TTL bucket, so they get **five minutes**
> even on a subscription until you choose a longer one."

| 请求桶 | 订阅内默认 TTL |
|---|---|
| 主对话 | **1 小时** |
| 其余（subagent / workflow / fork / compaction / 标题） | **5 分钟** |

⇒ 一个 subagent 如果两轮之间想超过 5 分钟（Opus 5 high effort 很常见），
它的整个上下文按全价重读。修法是一行设置：

```json
{ "subagentPromptCacheTtl": "1h" }
```

要求 Claude Code ≥ v2.1.242。⚠️ 超出套餐额度用 usage credits 时，
`1h` 会被忽略（官方明文）。

另一条：**fork 继承父会话前缀、能读父缓存；subagent 不能**。
「要结论就派 subagent」在缓存上是有成本的，不是白嫖。

---

## 4. 可直接照抄的诊断方法（官方，[高]）

v2.1.251+ 起 `/usage` 的 Session 区块有一行 **`Prompt cache (main)`**，
给出：命中率 / miss 次数 / 当前缓存是否 warm。
v2.1.260+ 起还会**点名上次 miss 的原因**，例如
`likely cause: tool definitions changed`。

> "A high read-to-creation ratio means caching is working well.
> **If creation stays high turn after turn, something is changing in your prefix.**"

⇒ 这是判「到底是不是缓存失效」的唯一权威判据，比任何估算都准。

补充：`claude -p "hello" --output-format json` 读 `usage.cache_creation`，
可确认拿到的是 1h 还是 5m 写入（`ephemeral_1h_input_tokens` / `ephemeral_5m_input_tokens`）。

---

## 5. 不失效缓存的动作（官方清单，可放心做）

改仓库文件 · **中途改 CLAUDE.md**（但也不生效，要 `/clear` 才加载）·
换 permission mode · 换 output style · **调用 skill 与 command** ·
`/recap` · **`/rewind`**（回到已缓存的前缀，比 `/compact` 便宜）· 派 subagent（对父会话无影响）

⚠️ 一条反直觉：`/rewind` 比 `/compact` 省——前者截断回一个**已经缓存过**的前缀，
后者必然重建对话层。全局 CLAUDE.md 里「跑歪了 Esc Esc 回滚」那条，
在成本上也是对的，不只是安全上。

---

## 6. 本仓库特有的三个放大器（对着代码，[高]）

| # | 现象 | 实测 | 机制 |
|---|---|---|---|
| 1 | `AGENTS.md` §10.6「改任何文件前完整读一遍」 | `BlindOrderStatusView.swift` 3188 行 = **51k tok**；`VolunteerOrderFlowViews.swift` 3616 行 = 47k | 进对话层，全价一次 + 永久占窗口。改两个界面 ≈ 98k 起步 |
| 2 | `AGENTS.md` §12「开搜前整份读 INDEX.md」 | 本文件 48 行 = **29k tok** | 每次联网调研前全价一次 |
| 3 | `research-log.mjs` PreToolUse | 每个联网工具调用注入 **12.1KB**（约 4k tok） | 本轮触发 4 次 ≈ 16k，纯重复（索引已在上下文里） |

第 3 条是**明确的缺陷**：钩子的意图是「保证开搜前读过索引」，
但它对同一会话内的第 2…N 次联网调用重复注入同一份内容，而那份内容已经在上下文里了。
判据应改为「本会话是否已注入过」，一次即可。

---

## 7. 被否掉的方案（留档）

| 方案 | 否决理由 |
|---|---|
| `ENABLE_TOOL_SEARCH=false` | §1.2，机制反了。会把 298k 工具定义搬回前缀并让 server 抖动炸缓存 |
| `permissions.deny` 屏蔽 `Pods/**`、`.build/**`、worktrees | Glob/Grep 走 ripgrep 且尊重 `.gitignore`，实测 `rg --files -g '*.swift'` = **220**（`--no-ignore --hidden` = 25483）⇒ 搜索面本来就干净。只留 `Types.swift`（281k tok）一条防手滑 |
| 清理 14G worktrees / 432M transcripts / 523M `scripts/openapi` | 占磁盘不占 token，与本议题无关 |
| 靠删 CLAUDE.md 省钱 | §2.1，缓存后每轮只占一成。删它的理由是窗口和信噪比，不是账单 |
| 降 Opus → Sonnet 做全部工作 | 官方 §2.2 的证据是「更少常驻指令不降表现」，不是「更小模型不降表现」。全局 CLAUDE.md 已有实测口径（Opus5@high 1606 Elo/$10.41 vs Sonnet5@max 1386/$14.43），不推翻 |

---

## 8. 未解决 / 需要实测

1. **本例到底是不是缓存失效造成的**——必须看 `/usage` 的 `Prompt cache (main)` 行。
   本轮只拿到 `/context`，`/usage` 与 `/mcp` 未提供。**这是本报告最大的空白。**
2. 本机 Claude Code 版本号未查，§1.2 的 2.1.69 bug、§3 的 v2.1.242 要求、
   §4 的 v2.1.251/260 要求均未核对适用性。
3. auto-memory 与手工 `memory/MEMORY.md` 是否双份计入（§2.4）。
4. 桌面端 connector（notion / gmail / canva / vercel / postman / gdrive）是 HTTP 传输，
   `/context` 显示已 defer，但 [#40314] 说 HTTP 不 defer——两者矛盾，未查清是版本差异还是
   连接器走的是另一条通道。

---

## 来源

- [How Claude Code uses prompt caching — Claude Code Docs](https://code.claude.com/docs/en/prompt-caching)（原文抓取，本报告 §1/§3/§4/§5 全部依据）
- [The new rules of context engineering for Claude 5 generation models](https://claude.com/blog/the-new-rules-of-context-engineering-for-claude-5-generation-models)
- [Using CLAUDE.md files](https://claude.com/blog/using-claude-md-files)
- [Best practices for Claude Code](https://code.claude.com/docs/en/best-practices)
- [anthropics/claude-code#30920](https://github.com/anthropics/claude-code/issues/30920) · [#30989](https://github.com/anthropics/claude-code/issues/30989) · [#40314](https://github.com/anthropics/claude-code/issues/40314)
- [Claude Code Token Consumption Diagnosis（社区，机制有误，见 §1.2）](https://yurukusa.github.io/cc-safe-setup/token-consumption-diagnosis.html)
