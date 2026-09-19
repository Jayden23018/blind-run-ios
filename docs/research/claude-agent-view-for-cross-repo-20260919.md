# Claude 的「agent view」能不能承接本项目的跨仓库长任务？

- 日期：2026-09-19
- 提问背景：项目负责人问「Claude 是不是有 agent view，把前端和后端联合起来，给一个任务让它一直做到完成」，并要求顺带盘点当前拖了很久没做完的事。
- 结论一句话：**能力是真的、跨仓库也真能做（比官方文档查到的更宽），但它解决不了本项目 64% 的积压 —— 那些积压卡在真机验证通道上，不卡在 agent 吞吐上。**

---

## 1. 能力盘点（逐项核实，标注来源性质）

| # | 能力 | 是什么 | 跨两个本地仓库？ | 来源性质 |
|---|---|---|---|---|
| 1 | **Agent View**（`claude agents`） | 从一块屏幕分发并管理多个**背景会话**，每个 prompt 起一个独立 session | ✅ **能**，见 §2 | 官方文档 + 本机 CLI 实证 |
| 2 | Agent Teams | 实验性（`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`），多个 teammate 各自独立上下文 | ❌ 无多仓库设计 | 官方文档 |
| 3 | Cloud sessions（`--cloud` / claude.ai/code） | 云 VM 克隆当前目录的 GitHub remote | ❌ 官方逐字 "`--cloud` works with a single repository at a time" | 官方文档 |
| 4 | Claude Agent SDK | Python/TS 库，把 Claude Code 的 agent loop 暴露给你自己写程序，**自己托管** | ✅ 自己写就能 | 官方文档 |
| 5 | Workflows | JS 脚本编排大量 subagent（默认并发 16，单次 `parallel()` 上限 4096，单次运行 1000 agents） | 脚本自定 | 官方文档 |
| 6 | `/loop` | bundled skill，会话开着时**反复跑同一个 prompt** | — | 官方文档 + 本 session skill 列表 |
| 7 | Headless（`claude -p`） | 非交互，供脚本/CI 调用；背景 Bash 有 10 分钟等待天花板 | 靠外层脚本 | 官方文档 |

**都不是**「给定验收条件后自主迭代直到满足」。最接近的是 `/loop`（重复执行）与 Workflows（脚本化 fan-out），两者的收敛条件都由你写死，不是模型自己判。

## 2. 🔑 订正一条：跨仓库**能**做，靠的是 `claude agents --add-dir`

联网调研的结论是「跨两个 git 仓库的官方能力查不到」。**那是只查文档没查本机 CLI 的结果。** 本机实测（2026-09-19，`claude agents --help`）逐字：

```
--add-dir <directory>   Additional directory to allow tool access to in dispatched
                        sessions (repeatable)
```

`repeatable` 三个字是关键：从 agent view 分发出去的每个背景会话，都能同时挂载 iOS 仓库与后端 `demo` 仓库。这与本仓库 `CLAUDE.md` 已有的「跨端任务一个 session 双挂载 `claude --add-dir /Users/mac/Downloads/demo`」是同一个机制，只是从「一个会话」扩到「一屏会话」。

顺带：`claude --bg` 逐字 "Start the session as a background agent and return immediately (manage with `claude agents`)" —— 命令行直接丢一个背景任务，回到 agent view 收。

⚠️ 与 `AGENTS.md` 不冲突：仓库写的是**不用 Agent Teams**（teammate 不继承 cwd），那条依然成立。Agent View 是另一个东西 —— 它分发的是完整会话，`--add-dir` 明确可重复。

## 3. 🔴 `/goal` 不存在 —— 全局 `CLAUDE.md:16` 是死引用

全局配置第 16 行写着：

> 终态可验证的长任务用 `/goal <条件>` —— 每轮由独立 checker 验，满足才收工

三处核实全部落空（2026-09-19）：

- `claude --help` 中 `grep -iE "goal|loop"` → **零命中**
- `/Applications/Claude.app`、`~/.claude`、`~/Library/Application Support/Claude` 下 `find -iname "*goal*"` → **零命中**
- 本 session 注入的可用 skill 列表里有 `loop`，**没有 `goal`**

联网侧同样只有社区博客（MindStudio 等）在讲 `/goal`，官方 `code.claude.com` 查不到。

**这条的代价不是措辞不精确，是它会被照抄。** 与记忆 `web-design-advice-is-mostly-not-for-swiftui` 记的同一形状：那次死引用的 `design-direction.md` 被任务书照抄了出去。真要「给定条件迭代到满足」，现成的写法是 `/loop` + 在 prompt 里写死验收判据，或者 Workflows 脚本里自己写 checker 循环。

## 4. 本项目能不能用：分两半

### 4.1 盘点结果（2026-09-19 当日）

GitHub Issues 在 `Jayden23018/blind-run-ios` 是**关闭**的，没有 issue 积压。真实待办在三处：

| 来源 | 数量 | 最老 |
|---|---|---|
| 未归档 OpenSpec 变更 | 14 个 / **42 条未完成** | `enable-independent-sos-safely`，首次提交 2026-07-10，**71 天**，7 条未完成 |
| 远端孤儿分支（领先 main 且落后 >30） | **30 条** | 最多落后 79 个提交 |
| 开着未合的 PR | 2 个（#151 / #152） | 2026-09-17，CI 全绿、mergeable |

42 条逐条读过，分布：

- **≈27 条（64%）是真机人工验证** —— 「开 VoiceOver 说一整句，听读回念得对不对」「低视力 AX3 以上字号看一眼不裁切」「真机批跑 —— 未执行，设备 `111` 本轮全程离线」
- 其余十几条是记账：归档顺序、`openspec validate`、commit/push/PR、以及几条标着「不适用 / 已投递后端」却没回来打勾的

`enable-independent-sos-safely` 的 7 条未完成**全部**是设备阻塞，含 `6.4 云端探针 —— 触发真实 SOS 会给紧急联系人发真短信并惊动客服`。SOS 到今天没在真机上验过。

### 4.2 判断

**积压的根因不是「没人写代码」，是「没人拿着手机验」。** 本仓库 CI 跑不了任何 XCTest（高德无 arm64-sim slice，模拟器通道永久不可用），真机是唯一通道，而真机每次都要人解锁屏幕、点信任证书、戴耳机听 VoiceOver。

⇒ **自主 agent 在这个项目上的天花板是「编译过了、PR 开了」**，最后一公里必然停在同一堵墙前。而仓库已有记忆 `merged-prs-whose-tests-never-ran` 记着后果：两批带红用例的代码因为「CI 全绿」进了 main —— CI 绿在这里只是编译信号。**给 agent 更多自主权，加速的是「未验证 PR」的生产速度。**

### 4.3 该用在哪（判据：验证是否依赖真机）

✅ **值得派**（结论可被一条命令核对，零真机依赖）：

1. **30 条孤儿分支逐条判活** —— 纯 git 判断，每条给出 `git diff --stat $(git merge-base origin/main origin/X) origin/X` 的独有改动 + 活/死结论。⚠️ 本仓库一律 squash 合并，`branch --merged` 与 `rev-list` 都会误报（记忆 `squash-merge-breaks-branch-merged-check`）
2. **openspec 记账对账** —— 把「已投递后端 / 不适用」却没打勾的条目对着 `demo/docs/handoff.md` 核一遍（记忆 `openspec-task-counts-lag-behind-handoff`：上次 65 条未完成里 8 条早已做完只是没回来打勾）
3. **契约同步类**（跨仓库，正好用 `--add-dir`）—— 前端调用路径 vs 后端 `api_spec.yaml`、错误码枚举对撞，这几条本来就有脚本

❌ **不要派**：那 27 条真机验证。它推不动，还会用「编译通过」冒充完成。

### 4.4 建议的第一步

先拿**孤儿分支判活**试水：任务边界清楚、纯只读、结论可逐条核对、失败代价为零。跑顺了再扩到记账与契约对账。

---

## 5. 🔴 本轮顺带挖出的缺口：「盲人点头才能开跑」这条链路前端零接入

推这份报告时被 pre-push 的生成代码漂移闸拦下（本轮只加了两个 md，不可能引入漂移 ⇒ 是主线既有状态）。重新生成的 diff 是 **450 行纯新增、0 删除**，内容不是样板，是后端 `start-service` 新加的两道闸：

| errorCode | 含义 | 契约逐字要求客户端怎么做 |
|---|---|---|
| `SERVICE_START_TOO_EARLY` | 距 `plannedStartTime` 还有超过 15 分钟 | 「按钮置灰，到点再亮」 |
| `BLIND_CONFIRMATION_PENDING` | 盲人还没调 `POST /api/orders/{id}/confirm-start` | 「提示『等待对方确认』，**不要**置灰 —— 对方随时可能点」 |

契约另有逐字一句：「盲人点头时陪跑员会收到 `BLIND_START_CONFIRMED` 通知 —— **客户端接上它**，否则志愿者只能反复点按钮试探。」

**核实结果（2026-09-19，排除 `Packages/AidRunAPI/` 生成代码目录）**：

| 符号 | 后端 `origin/main` | iOS 前端 |
|---|---|---|
| `BLIND_CONFIRMATION_PENDING` | 16 处（CHANGELOG + api_spec + handoff） | **0 处** |
| `SERVICE_START_TOO_EARLY` | 14 处 | **0 处** |
| `BLIND_START_CONFIRMED` | 14 处 | **0 处** |
| `confirmStart` / `confirm-start` 调用点 | 端点已上线 | **0 处**（13 处 `confirm-start` 全在 worktree 里一份遗留 Flutter 审计文档引用旧 OpenAPI，不是实现） |

**后果链**：志愿者到现场点「开始陪跑」→ 后端 409 `BLIND_CONFIRMATION_PENDING` → 前端不认识这个码，落未知错误分支 → 而盲人端**根本没有点头的地方** ⇒ 两个人站在一起，只能干等到 `plannedStartTime + 15 分钟` 宽限自动放行。对盲人端「点了没反应」就是事故（`AGENTS.md` 既有红线）。

按 skill `aidrun-contract-sync` 的分流判据，这条**触及盲人端红线（未知错误码 + 主流程卡死），应单独开变更并带测试**，不并入其他 PR。本轮只做记账，不实现 —— 盲人端按钮放在哪一态、VoiceOver 怎么念、`DRIVER_ARRIVED` 那屏的信息架构，都需要设计决策。

⚠️ 这条同时是 §4 结论的一个反例补充：**它不需要真机就能发现**（两条 grep + 一次 pre-push），属于 §4.3 里「值得派」的第 3 类（跨仓库契约对撞）。也就是说 agent view 在这个项目上真正的价值，是把这类**只读、可机器核对**的缺口挖出来，而不是替人去验真机。

## 6. 未解决 / 未做

- Agent View 分发的背景会话**能不能跑 `scripts/device-test.sh`** 并正确处理「设备锁屏立即失败」—— 未实测，本轮设备未连接
- Workflows 的 1000 agents / 并发 16 是官方数字，**本机未压测**
- `claude agents` 的完整选项只看了前 20 行，分发会话的权限模型（`--dangerously-skip-permissions` 在背景会话里的实际边界）未细查
- Managed Agents（`platform.claude.com`，Anthropic 托管、REST 调用）本轮只确认存在，未评估
