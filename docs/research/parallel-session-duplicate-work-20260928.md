# 并行会话重复做同一件事、PR 堆积与合并冲突：根因与工作流建议（2026-09-28）

## 问题

项目负责人的工作流：一个会话盘点仓库「已做 / 没做」→ 列成 suggested task 卡片 → 逐个点「start with worktree」
开新会话 → 各自开 PR、合 PR。开得多了之后出现：有的会话没开 PR、有的开了没合；新会话看不到别的会话
已经改完的东西，以为没做又做一遍，或在别处「顺手」再建议一次；rebase 和合并冲突频繁。
前后端两个仓库都有这个问题。

## 一、本机实测（2026-09-28 取值）

| 指标 | 前端 blind-run-ios | 后端 demo |
|---|---|---|
| `git worktree list` 条数 | 37 | 22 |
| 开着的 PR | 8（最老 #173，09-21） | 16（最老 #268，09-11；其中 5 个 dependabot） |
| 远端分支有独有提交且落后 main >30 | 41 | 22 |
| 09-10 以来合并的 PR | 93 | 72 |
| SessionStart 注入在途 PR？ | 否 —— `scripts/hooks/session-context.mjs:120` 明写「不查 PR 状态」 | 没有 SessionStart 钩子 |
| Stop 钩子管 PR 开没开 / 合没合？ | 否，只管 commit + push | 否，只有调研归档 / 编译 / 文档提醒 |
| `spawn_task` 有没有钩子 | 无 | 无 |

重复劳动的实证（前端）：
- Stop 钩子「无 upstream」误报前后修了三次：#180（合）→ #186（关）→ #190（合，含同一件事）；
  另有 worktree `claude-docs-skills-review-8248ed` 挂着分支 `fix/stop-checklist-squash-false-positive`。
- 容器 identifier 覆盖子元素这一类问题分三次修：#182、#183、#243（记忆里记的是「三次」）。
- #185（新 worktree 自动带 LocalConfig）和 #186 都是在 #190 合并后关掉的，关闭评论逐字
  「内容已收入 #190（squash 合并）」—— 同一件事在两个会话里各做了一遍，最后靠人工对账收拢。

新 worktree 的基点（实测）：`.claude/worktrees/` 下 `blissful-goldstine` / `magical-moser` / `relaxed-jackson`
三个都建在 09-26 16:18，基点都是 `a55eadc`；main 上 `a55eadc` 的下一条提交在 16:26 才合进去
⇒ **基点就是当时的 `origin/main`，一点不旧；看不见的是还没合并的 PR**。
同一分钟连开三个，也说明卡片是成批启动的。

## 二、官方文档事实（2026-09-28 核实）

1. **worktree 基点**：`worktree.baseRef` 默认 `"fresh"`，即
   "branch from the repository's default branch on the remote, usually main"；
   另一个取值 `"head"` 是 "branch from your current local HEAD"。fresh 模式下
   "when the repository hasn't been fetched in the last 24 hours, it fetches the default branch, capped at five seconds"。
   来源 https://code.claude.com/docs/en/worktrees.md
2. **任务卡**：桌面文档只写了
   "When it notices something worth fixing that's out of scope for the current task, it offers the work as a task chip"，
   点开后 "start that work in a new session with its own worktree"。没有写 prompt 会不会在开工时刷新，
   也没有写去重。来源 https://code.claude.com/docs/en/desktop.md
3. **认领 / 锁**：普通 worktree 并行会话之间**没有**认领机制。只有实验性、默认关闭的 Agent Teams 有：
   "Task claiming uses file locking to prevent race conditions"，而且只在同一个 team 的共享任务列表内生效。
   来源 https://code.claude.com/docs/en/agent-teams.md
4. **钩子路径**：worktree 会话里 `${CLAUDE_PROJECT_DIR}` "still points at the project root where the session started"，
   worktree 路径要读钩子输入 JSON 里的 `cwd`（"the cwd field in the hook's input JSON is the worktree root"）。
   来源 https://code.claude.com/docs/en/hooks.md
5. `WorktreeCreate` 钩子会 "Replaces default git behavior"，任何非零退出都会让创建失败。来源同上。

## 三、根因

1. **新会话只看得见已合并的东西，这是设计本身**（二.1 + 一的实测）。在途 PR 里的改动对新 worktree 不可见，
   只要「开 PR → 合进去」之间有时间差，这段时间里开的会话就会重做一遍。
2. **任务卡是写死的快照，没有编号，也没有「有人在做」的状态**（二.2、二.3）。规划会话出卡片时不查在途 PR；
   干活的会话「顺手」建议时也不查。点开一张卡，谁都不知道它已经被做过了。
3. **本仓库的钩子恰好在这里留了空**：开场不注入在途 PR，收尾不管 PR 开没开、合没合（一的表）。
4. **在途量太大**：前后端合计 59 个 worktree、24 个开着的 PR、63 条陈旧分支。并行越多，改到同一批文件的概率越高，
   rebase 和冲突随之增加。重复劳动和合并冲突是同一个原因的两个症状。
5. **规则打架**：全局 `CLAUDE.md` 同时写着「范围外问题建 issue 放看板」和「不要自己合并 PR，等我审」；
   而实际做法是会话弹 chip（不建 issue）、会话自己合并。两条通道并存、谁都不去重，
   PR 就停在「开了、等人审」这一步。

## 四、建议（按性价比排序）

| # | 做什么 | 解决哪条根因 | 成本 |
|---|---|---|---|
| 1 | **Issue 作为唯一的任务单位和认领锁**：规划会话先 `gh issue list` + `gh pr list --state open` 去重 → 每个任务建 issue → 再弹 chip，chip prompt 第一行写 `处理 #N`；干活的会话第一步 `gh issue view N` + `gh pr list --search N`，已有 PR 或看板 Status 已是 In Progress 就停下报告。PR 写 `Fixes #N`，合并时自动关 issue | 2、5 | 只改规则（全局 `CLAUDE.md` 一段） |
| 2 | **SessionStart 注入在途清单**：`gh pr list --state open --json number,title,files`，加 3 秒超时，失败就跳过（原来不查是怕开场卡住，加超时就解决了）。后端也补一个 | 1、3 | 前后端各约 20 行 |
| 3 | **`spawn_task` 挂 PreToolUse 钩子**：prompt 里没有 `#数字` 就拒绝，提示先去重并建 issue。把第 1 条规则变成机器检查（§1.1） | 2 | 约 15 行；✅ 2026-09-28 实测桌面进程内的 `mcp__ccd_session__spawn_task` **会**走 PreToolUse，改 `settings.json` 后当场生效 |
| 4 | **Stop 钩子补 PR 检查**：分支已推送、领先 main，但 `gh pr list --head <分支>` 为空 → 拦住，要求开 PR | 3 | 约 15 行 |
| 5 | **开 PR 时直接打开 GitHub auto-merge（squash）**，CI 绿了自动合，「开了没合」这个状态就没了 | 1、5 | 仓库设置开 auto-merge + 分支保护必需检查；**要负责人拍板**，和「不要自己合并」那条规则冲突 |
| 6 | **WIP 上限**：同一个仓库同时最多 3 个会话；规划时给每张卡标预计会改的目录，目录有重叠的合成一张或串行（卡里写「等 #N 合并后再开始」） | 4 | 只改习惯 |
| 7 | **一次性清仓**：逐条判活 59 个 worktree / 24 个 PR / 63 条分支（合 / 关 / 删） | 4 | 一个专门的会话 |
| 8 | 开工和开 PR 前各 `git fetch && git rebase origin/main` 一次 | 1 | 规则一句 |

### 否掉的方案

- **Agent Teams**（官方唯一带认领锁的机制）：实验性、默认关闭，锁只在同一个 team 内生效，管不到桌面的任务卡；
  全局 `CLAUDE.md` 已判定本仓库不用（teammate 不继承 cwd）。
- **`worktree.baseRef: "head"`**：会把主 checkout 当前所在分支（它常停在别人的特性分支上）带进新 worktree，
  比现在更乱；而且未合并的 PR 分散在各个分支上，没有一个 HEAD 能把它们都装下。
- **用 `WorktreeCreate` 钩子把在途 PR 合进基点**：等于把没审过的代码塞进每个新会话，冲突只会提前，不会消失。

## 五、落地（2026-09-28，负责人批准当天）

| # | 状态 | 落点 |
|---|---|---|
| 1、6、8 | ✅ 规则 | `~/.claude/CLAUDE.md`「任务追踪」节：认领前查在途 PR、弹卡前去重建 issue、卡片带 `#N`、目录重叠串行、WIP≤3、开工与开 PR 前 rebase |
| 2、3、4 | ✅ 钩子 | 全局 `~/.claude/hooks/inflight.py`（session / spawn / stop 三个模式，一份脚本管前后端），注册在 `~/.claude/settings.json`；自测 `test-inflight.py` 通过，两处变异（Stop 永不拦、卡片永远放行）各自能让自测变红 |
| 5 | ⛔ 未落地 | 自动模式的安全分类器把「开 auto-merge + 加分支保护」判为 CI Bypass 拦下，需负责人本人执行。另：后端是免费账号下的私有仓库，分支保护与 rulesets 均 403，**GitHub 原生 auto-merge 在后端不可用** |
| 7 | 🟡 清单已出 | 前端 26 个 / 后端 15 个可安全删除（PR 已合或零提交，且工作区干净），等负责人确认。清单里发现一处重复实锤：未推送分支 `feat/guide-run-live-activity`（12 个独有提交）与开着的 #231 是同一功能 |

放全局而不是分别放进两个仓库：前后端同病，一份脚本 + 一份自测就够；只认 origin，所以 `gh` 默认打到 upstream 的坑不影响它。

## 复核触发条件

桌面 App 给任务卡加去重或认领；`worktree.baseRef` 增加新取值；Agent Teams 转正或支持跨会话；
本仓库改成必须人工审 PR 才能合并。
