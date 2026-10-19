# AGENTS.md 瘦身与 SessionStart 注入精简（#482）

> 状态：**负责人已确认**（2026-10-19）。#371 合并前不实现；实现在新会话里做。
> 面试记录：本文件「决策」表就是结论，不需要再翻原会话。

## 目标

`CLAUDE.md:1` 的 `@AGENTS.md` 每个会话无条件加载，实测占首轮输入约 **18.7k token**（见「现状」）。
把 AGENTS.md 压到 **≤ 16,384 字节且 ≤ 200 行（只计会被注入的部分）**：只留硬约束和 skill 路由表，
「怎么做」的细节下沉到 skill，历史说明改成 HTML 注释（留给人看、不进上下文）。
同时把 SessionStart 钩子的 OpenSpec 那一行从「逐个列名」改成只报计数。
再加一道 CI + pre-push 体积闸，防止它像上次那样（09-05 的 22.6KB → 今天 51.7KB）长回去。

## 现状（2026-10-19 实测）

| 项 | 数值 | 怎么得到的 |
|---|---:|---|
| `AGENTS.md`（worktree HEAD `81f2c4f2`） | 51,714 B / 568 行 | `wc -c` |
| `AGENTS.md`（`origin/main` `6c625952`） | 51,938 B | `git show origin/main:AGENTS.md \| wc -c` |
| 其中 `>` 引用块（几乎全是历史说明） | 13,882 B / 142 行 | 按行首 `>` 统计 |
| 首轮输入，AGENTS.md 原样 | 78,200 token | 见「验收 §3」的 `measure` 命令，临时 worktree |
| 首轮输入，AGENTS.md 清空 | 59,468 token | 同上 |
| 首轮输入，AGENTS.md 整个包进 `<!-- -->` | 57,317 token | 同上 ⇒ **@import 进来的 AGENTS.md 里的块级 HTML 注释确实被剥掉** |
| 同一命令在两个不同 worktree 的差 | 约 2k token | 噪声量级，所以验收取 3 次中位数 |
| SessionStart 输出（worktree 里当前版本） | 2,490 B | `node scripts/hooks/session-context.mjs \| wc -c` |
| SessionStart 输出（桌面 App 实际注入的） | 4,790 B | 执行的是主 checkout 的旧版钩子，见 #483 |

依据：官方文档 <https://code.claude.com/docs/en/memory>（2026-10-19 用 fetch 读原文）——
「Block-level HTML comments (`<!-- maintainer notes -->`) in CLAUDE.md files are stripped before the content is injected」；
「Imports … don't reduce its context cost, because imported files also load at launch」；
「target under 200 lines per CLAUDE.md file」；path-scoped rule「loads when Claude uses the Read, Write, or Edit tool on a matching file」。

⚠️ 账单预期要说准：仓库 `docs/research/claude-code-token-optimization-20260917.md` 已查明常驻内容是「首轮全价写缓存 + 之后每轮约一成读缓存」。
删 AGENTS.md 省的主要是**窗口占用与信噪比**，以及每个新会话首轮那次缓存写入；**省不掉缓存失效的代价**。别在 PR 里宣称「额度消耗降低 X%」，只报实测 token。

## 范围

做：
- 按下面「段落去向表」改写 `AGENTS.md`，**保留 §0–§13 节号不变**（理由见决策表）。
- 新建 skill `.claude/skills/aidrun-order-and-sos/SKILL.md`，承接 §5 / §6 下沉的细节；在 §0 路由表加一行。
- 把 §11 的命令与门禁细节并进已有的 `.claude/skills/aidrun-ship-check/SKILL.md`（只补它缺的，不复制已有的）。
- 改 `scripts/hooks/session-context.mjs` 的输出格式（见「SessionStart 新格式」），同步改它的自测 `scripts/validate-session-context.mjs`。
- 新建 `scripts/validate-agents-size.mjs`（体积闸，带自测），接进 `.github/workflows/verify.yml` 与 `scripts/hooks/pre-push.sh`。
- 删掉 AGENTS.md §9 里写死的团队号（当前 `AGENTS.md:351`）—— 它与 `CLAUDE.md`「这里和任何文档都不写具体团队号」直接冲突。

**不做**（明确排除）：
- 不修「worktree 会话执行主 checkout 旧版钩子」—— 已单开 #483。本 SPEC 的 SessionStart 改动在桌面 worktree 会话里**要等主 checkout 更新后才生效**，验收只在 CLI 里测。
- 不改 `CLAUDE.md`（2,979 B，与 AGENTS.md §7/§11 有几行重复）—— 负责人 2026-10-19 确认不在本次范围。
- 不改任何规则的**含义**。每条硬约束要么原样（可压缩措辞）留在 AGENTS.md，要么搬到写明的去处；不许有规则凭空消失。
- 不改 `MEMORY.md` 与项目记忆文件。
- 不建 `.claude/rules/`（面试时否掉了 paths 规则，理由见决策表）。
- 不动 App 源码，因此**不需要 OpenSpec 变更**（不改变 App 行为）。

## 涉及的文件与接口

| 文件 | 改什么 |
|---|---|
| `AGENTS.md` | 按去向表重写；注入部分 ≤ 16,384 B 且 ≤ 200 行 |
| `.claude/skills/aidrun-order-and-sos/SKILL.md` | **新建**。frontmatter `name: aidrun-order-and-sos`；description 写清触发场景：改订单状态流转、取消入口、派单 `respond`、通话磨合（`PENDING_INTRO_CALL`）页、任何求助 / SOS 入口与降级拨号时读 |
| `.claude/skills/aidrun-ship-check/SKILL.md` | 只补 §11 里它没有的内容（§二 已有命令块、§六 已有跑多大范围、§七 已有 5 条门禁 —— 先 diff 再补）；再把 §9 那条「取守卫规则 id 的 python 命令」放进 §八（事故复盘，加守卫时用） |
| `scripts/hooks/session-context.mjs:34-53` | OpenSpec 那段改成只报计数，见下 |
| `scripts/hooks/session-context.mjs:121-141` | 陈旧分支那行改成只报条数 + 查看命令，不列名 |
| `scripts/validate-session-context.mjs` | 同步断言：输出里不出现变更名（「待归档」除外）、计数正确、陈旧分支不列名 |
| `scripts/validate-agents-size.mjs` | **新建**。读 `AGENTS.md`，剥掉块级 HTML 注释（`<!--` … `-->`，代码块内的不剥，与官方行为一致）后算字节和行数；超 16,384 B 或 200 行就 exit 1 并打印两项实际值。带 `--self-test`：内置 3 个用例（见验收 §2） |
| `.github/workflows/verify.yml` | 在 `validate-session-context` 那一步旁加 `node scripts/validate-agents-size.mjs` 与 `--self-test` |
| `scripts/hooks/pre-push.sh:78` 附近 | 同上，放在默认档（每次 push 都跑，它只要几毫秒） |

## 段落去向表

行号以 `81f2c4f2` 为准；#371 合并后先 rebase，再按标题重新对行号（#371 改了 AGENTS.md 4 行，`CONTEXT.md` → `GLOSSARY.md`）。
「目标字节」是建议分配，合计约 15.1KB；只有总量受闸门约束。

| 段落 | 行 | 现字节（其中引用块） | 类型 | 去向 | 目标字节 |
|---|---|---:|---|---|---:|
| 开头 + 仓库边界 | 1–6 | 484 | 硬约束 | 留 | 480 |
| §0 skill 路由表 | 7–19 | 1,261 | 路由 | **留**，加 `aidrun-order-and-sos` 一行 | 1,350 |
| §0 swiftui-pro「部署目标 iOS 16」警告 | 21–24 | 478 | 硬约束 | 留，压成 1 行 | 150 |
| §0 design-direction / mockups INDEX | 26–34 | 958 | 路由 | 留，压成 2 行（`design-direction-reminder.mjs` 已在动视图时提醒） | 300 |
| §0「Web 设计建议对 SwiftUI 有害」 | 36–44 | 885 | 细节 | 删正文；在 §1 查找表加一行指向记忆 `web-design-advice-is-mostly-not-for-swiftui` | 0 |
| §0 词表（`GLOSSARY.md`，#371 后的名字） | 46–49 | 502 | 路由 | 留 1 行 | 180 |
| §1 复盘规则本体（四种归宿 + 卡很久 + 反复查） | 51–69 | 1,552 | 硬约束 | 留，压缩措辞；例子挪进 HTML 注释 | 700 |
| §1 症状 → 记忆查找表 | 71–90 | 2,041 | 路由 | **留**；症状列压短；加两行（弹性 Spacer、Web 设计建议） | 1,600 |
| §1 表的由来说明 | 92–96 | 459（459） | 历史 | HTML 注释 | 0 |
| §1「看着怪但说不出哪儿怪」弹性 Spacer 段 | 98–110 | 1,255 | 细节 | 删正文，变成查找表一行（记忆 `flexible-spacer-steals-half-the-row` 已有全文） | 0 |
| §2 源真相 | 111–122 | 540 | 硬约束 | 留 | 540 |
| §3 生产方向 | 123–135 | 1,526（359） | 硬约束 | 留；`>` 那段（http→https 由来）改 HTML 注释 | 1,000 |
| §4 范围 | 136–139 | 348 | 硬约束 | 留 | 340 |
| §5 状态列表 + 禁用词 | 140–151 | 515 | 硬约束 | 留 | 500 |
| §5 流转图 | 152–185 | 1,332 | 细节 | → skill | 0 |
| §5 取消 / 端点 / 下单上限细则 | 186–199 | 3,035 | 细节 | → skill；**以下几条压成一行一条留在 §5**：盲人在 `DRIVER_EN_ROUTE`/`IN_PROGRESS` 不得出现取消入口；`DRIVER_ARRIVED` 取消门槛只认 `earliestBlindCancelAt`、客户端不自己算；`confirm-departure` 与 `en-route` 不许合并；`DUPLICATE_ORDER` 只拦时段冲突 | 见下行合计 |
| §5 `PENDING_INTRO_CALL` | 200–232 | 5,498（1,629） | 细节 | → skill（引用块随段落一起搬，留 `>` 原样）；**留在 §5 一行一条**：磨合没成退回 `PENDING_MATCH` 不是 `REMATCHING`；发 `ACCEPT` 还是 `INTERESTED` 只认推送里的 `requiresIntroCall`；掩码串绝不拼 `tel:`；客户端不许自己算轮次 | §5 合计 ≈ 1,400 |
| §6 SOS 红线条目 | 233–236、307–317 | 2,003 | 硬约束 | 留：只在 `IN_PROGRESS` 走云端、其余一律本地拨号且不调 `/api/emergency/trigger`、新增入口必须读那一端的 `*SOSMode.resolve`、志愿者无「误触」、永不宣称短信已送达、坐标拿不到就不发、确认文案逐字锁定（原样保留代码块） | 1,800 |
| §6 三处求助入口清单与订正史 | 237–306 | 7,048（4,555） | 细节 + 历史 | → skill（引用块随段落搬） | 0 |
| §7 外部 API 契约 | 318–324 | 970 | 硬约束 | 留，压缩 | 600 |
| §8 iOS 硬规则 | 325–346 | 2,119（299） | 硬约束 | 留；`>` 那段改 HTML 注释；「判据是取值空间封不封闭」压成 2 行 | 1,300 |
| §9 冻结规则 | 347–354 | 598 | 硬约束 | 留，**删掉写死的团队号** | 450 |
| §9 由来 + 取规则 id 命令 | 355–376 | 1,736（1,735） | 历史 | 由来 → HTML 注释；命令 → `aidrun-ship-check` §八 | 0 |
| §10 开工（含 SessionStart 说明） | 377–398 | 1,640（1,303） | 硬约束 + 历史 | 三步留；引用块 → HTML 注释 | 300 |
| §10 实现中 + 读文件表 | 399–420 | 1,552（597） | 硬约束 + 细节 | 留「一次一个模块」「行为有变先有 OpenSpec 变更」「改前自己读」+ 一行「≥500 行用 `codegraph node <符号>`」；表与实测 → HTML 注释 | 500 |
| §10 收尾三件事 | 421–435 | 1,468（339） | 硬约束 | 留，引用块 → HTML 注释 | 500 |
| §10 OpenSpec 闭环说明 | 436–443 | 651（650） | 历史 | 留 1 行，其余 HTML 注释 | 100 |
| §10 共享 checkout 三条 | 444–466 | 1,928（393） | 硬约束 | 三条原样留；引用块 → HTML 注释 | 900 |
| §11 命令块 + 说明 | 467–499 | 1,945（290） | 细节 | → `aidrun-ship-check`；留 3 行：CI 跑不了 XCTest 只能真机、零执行不是通过、默认只跑覆盖改动的 suite（见 skill §六） | 350 |
| §11 读后端仓库的 5 条门禁 | 500–518 | 1,534 | 细节 | → `aidrun-ship-check` §七（先 diff）；留 2 行：两端同改必须后端先合、⛔ 别用 `AIDRUN_SKIP_PREPUSH=1` | 250 |
| §12 调研落盘 | 519–554 | 2,802（904） | 硬约束 | 留 4 条规则；钩子说明与由来 → HTML 注释 | 600 |
| §13 review 落盘 | 555–568 | 1,044（370） | 硬约束 | 留，引用块 → HTML 注释 | 400 |

**新 skill `aidrun-order-and-sos` 的结构**：`## 订单状态机`（流转图、取消流转与权限、端点、下单上下限）→ `## PENDING_INTRO_CALL` → `## 求助入口`（三处入口清单、降级拨号、各入口的用例名）。
内容**原文搬运**，只删与 AGENTS.md 留下部分逐字重复的句子；开头一句写明「红线在 AGENTS.md §5/§6，本文件是细节，冲突以 AGENTS.md 为准」。

**HTML 注释的写法**：用块级 `<!-- … -->` 原地包住，放在它解释的那条规则下面；注释里出现 `-->` 时要改写，否则会提前结束注释。

## SessionStart 新格式

现在 OpenSpec 那一行逐个列出 30 个变更名（约 1.5KB）。改成：

```
- OpenSpec 未归档 30 个：进行中 M、未开工 U、任务全勾待归档 K。列表：`openspec list`。
- ⚠️ 待归档（全勾却没归档，Stop 钩子会拦）：<名字1>、<名字2>
```

- **进行中** = `tasks.md` 里至少一项 `- [x]` 且至少一项 `- [ ]`；**未开工** = 一项都没勾；**待归档** = 全勾。没有 `tasks.md` 的目录照旧跳过。
- 第二行只在 K > 0 时输出。
- 删掉「⚠️ 多个未归档变更同时存在时，先确认……」那一行：30 个变更时它每次都响。按本钩子自己写的原则（`session-context.mjs:97`「全绿时不输出……只报缺口」），每次都响的提醒会被无视。
- 陈旧分支那行改成：`⚠️ N 条远端分支有独有提交却长期没跟进（领先 main 且落后 >30）。查看：<一条能列出它们的 git 命令>。` 不再列名。
- 分支 / 脏文件、后端契约源、pre-push 未装三行**不动**。
- 目标：整段输出 ≤ 1,000 B（今天 worktree 版 2,490 B）。

## 决策

| 决定 | 理由 | 否掉了什么 / 为什么否 |
|---|---|---|
| 方向照 PR #109 重做 | 负责人确认 #109 关掉是「忘了合 / 冲突」，不是方向被否 | — |
| §5/§6 红线留、细节进**新 skill** `aidrun-order-and-sos` | 本仓库路由表 + skill 的组合 30 天被调用 73 次，是已证明有效的通道 | **paths 规则**（`.claude/rules/` + `blindRun/Safety/**`）：规划阶段不在场、`/compact` 后不重注入（demo `CLAUDE.md:38` 记过这个盲区）。**§5/§6 全部常驻**：两节合计 19KB（37%），留着就到不了 16KB |
| 历史说明改 **块级 HTML 注释**，原地保留 | 官方文档写明块级注释注入前被剥掉；本 SPEC 已实测 @import 的 AGENTS.md 同样被剥（57,317 vs 原样 78,200 token）；维护的人改规则时就在旁边看到由来 | **搬到单独的历史文件**：和规则分开就没人一起维护。**直接删**：由来是「为什么别改回去」的唯一说明，删了下次有人原样改回去 |
| 随段落搬进 skill 的引用块保持 `>` 原样 | skill 只在被调用时加载，引用块在那里不是常驻成本；改注释还得另验 skill 是否也剥注释 | 在 skill 里也改 HTML 注释：多一道没验证过的假设，收益小 |
| 体积闸：注入部分 ≤ 16,384 B 且 ≤ 200 行，CI + pre-push 硬拦 | 22.6KB → 51.7KB 只用了 6 周，按 AGENTS.md §1.1「能被静态检查抓到的就写守卫」 | **只在 Stop 钩子提醒**：提醒会被跳过。**不加**：#109 之后就是这么长回去的。12KB：§1 查找表与 §10/§11 也得搬走。20KB：涨回来更快 |
| 闸门只数**会被注入**的部分（剥掉 HTML 注释后） | 注释不占上下文；按文件原始字节算会逼人删由来 | — |
| 保留 §1 症状 → 记忆查找表 | 它按「看到的报错」索引，`MEMORY.md` 按主题索引，遇到报错时只有前者查得到 | 删掉靠 MEMORY.md：省 2KB，但按症状找不到 |
| §0–§13 节号保持不变 | `scripts/hooks/guard.mjs:29,34,45,161,175,178,194` 的注释与报错文案、`validate-guard.mjs:151,1434`、`stop-checklist.mjs:210` 等都按「AGENTS.md 第 N 节」引用；记忆文件也是 | 重新编号：要同步改十几处，漏一处就是死引用 |
| SessionStart 只报计数 + 「待归档」名字 | 30 个名字每次 1.5KB，几乎从不被用到；「待归档」是唯一要当场动手的，通常 0–2 个 | 连待归档也不列：Stop 钩子会因它拦人，开场就该知道是哪个 |
| worktree 跑旧钩子的问题单开 #483 | 它影响全部 8 个钩子，超出本 issue 范围 | 并进本 issue：范围翻倍，且 `$CLAUDE_PROJECT_DIR` 的解析方式还没查清 |
| SPEC 放 `docs/specs/` | 仓库原本没有 SPEC 的固定位置；进 git 方便实现会话与 PR 引用 | 仓库根 `SPEC.md`：做完要删，多个 spec 会冲突。只放笔记目录：别的机器看不到 |

## 实现顺序

1. `gh pr view 371 --repo Jayden23018/blind-run-ios --json state` 必须是 `MERGED`，否则停下报告（#371 改 AGENTS.md 4 行，不等它会冲突）。
2. 从最新 `origin/main` 开新分支；按标题重新对去向表的行号。
3. 先写 `scripts/validate-agents-size.mjs` 和它的自测，确认对**当前** AGENTS.md 报红（RED）。
4. 建 `aidrun-order-and-sos`、补 `aidrun-ship-check`（先搬出去，再从 AGENTS.md 删，避免中途丢内容）。
5. 改写 AGENTS.md，直到体积闸转绿。
6. 改 `session-context.mjs` 与自测。
7. 跑「验收」全部命令；用新鲜 subagent 对照本 SPEC 的去向表核 diff（见验收 §5）。

## 验收

```bash
# §1 体积闸：改完必须绿；对改之前的 AGENTS.md（git show origin/main:AGENTS.md）必须红
node scripts/validate-agents-size.mjs

# §2 体积闸自测：三个用例都要过
#   ① 16,385 B 的正文 → 红   ② 16,384 B 正文 + 50KB HTML 注释 → 绿   ③ 201 行短行 → 红
node scripts/validate-agents-size.mjs --self-test

# §3 首轮 token 对照：main 与本分支各跑 3 次，取中位数
measure(){ claude -p "只回复 OK，不要调用任何工具" --output-format json --max-turns 1 2>/dev/null \
  | python3 -c 'import json,sys;u=json.load(sys.stdin)["usage"];print(u["input_tokens"]+u.get("cache_creation_input_tokens",0)+u.get("cache_read_input_tokens",0))'; }
# 在 origin/main 的临时 worktree 和本分支 worktree 里各跑 3 次 measure

# §4 SessionStart 输出
node scripts/hooks/session-context.mjs | wc -c      # ≤ 1000
node scripts/hooks/session-context.mjs              # 目视：没有变更名（待归档除外）、没有分支名列表

# 既有门禁不能红
node scripts/validate-session-context.mjs
node scripts/validate-guard.mjs
node scripts/validate-stop-checklist.mjs
node scripts/validate-docs.mjs
openspec validate --all --strict --no-interactive
```

通过标准：
- §1 绿，并贴出「字节 / 行数」两个实际值；对旧 AGENTS.md 报红。
- §2 三个用例全过。
- §3 本分支中位数比 main **少 ≥ 12,000 token**（AGENTS.md 现约 18.7k，压到 16KB 约剩 5.8k；扣 2k 噪声）。PR 里贴 6 个原始数。
- §4 ≤ 1,000 B。
- §5 **规则不丢**：新鲜 subagent 拿 `git diff origin/main -- AGENTS.md .claude/skills/` 和本 SPEC 的去向表，逐行核对：
  每个被删的段落都能在「留下的一行 / skill 某节 / HTML 注释」三处之一找到，或在去向表里写明「删」；
  §5/§6 去向表点名要留的每一条红线都还在 AGENTS.md 里。报告写进 PR 描述。
- 全部既有门禁绿。

## 未决 / 需要人拍板

- 桌面 App worktree 会话里，SessionStart 的改动要等 #483 解决或主 checkout 更新后才看得到。本 SPEC 只在 CLI 里验收。
