---
name: aidrun-hooks-and-guards
description: AidRun 的 6 个钩子与守卫在拦什么、判据为什么长这样、怎么自测；冻结文件清单与理由；review 落盘位置。被钩子或守卫拦住、要改构建相关文件（Podfile / pbxproj / EXCLUDED_ARCHS）、要改钩子本身、或要落一份成体系的 review 时读。
---

# AidRun 钩子与守卫

从 `AGENTS.md` §9 / §10 / §13 拆出。**规则本身仍在 `AGENTS.md`，这里是理由、命令与踩坑史** ——
被拦住了不知道为什么、或要动钩子本身时读这份。

## 一、冻结文件（`AGENTS.md` §9 的完整版）

**整文件冻结**：`Podfile` —— 架构排除设置与 pod 列表都在里面，没有安全的局部改法。

**行级冻结**：`blindRun.xcodeproj/project.pbxproj` —— 文件可以改（例如加 SPM 依赖），但改动内容**不得触及 `DEVELOPMENT_TEAM`**。写死的 `R6PH2TFB3Q` 是原开发者的团队号，命令行传 `DEVELOPMENT_TEAM=ZW39BS8NXT` 覆盖。

**任何构建相关文件都不得写入 `EXCLUDED_ARCHS`** —— 真机是唯一 XCTest 通道，模拟器因高德无 arm64-sim slice **永久不可用**，那条设置是这个事实的载体。确需在代码或注释里提及，行尾加 `guard:allow excluded-archs`。

> 2026-08-06 从整文件冻结改为行级。核对后发现原先给的两条理由只有一条落在 pbxproj 上（`DEVELOPMENT_TEAM`，12 处）；`EXCLUDED_ARCHS` 在 pbxproj 里出现 **0 次**，它只存在于 `Podfile:36`。整文件冻结的代价是连加一个 SPM 依赖都做不到，而「临时解锁、改完加回来」依赖人记得加回来 —— `AGENTS.md` §1 说的就是这种挡不住重复犯错的做法。

### 守卫规则清单：**这里一律不写，当场取**

守卫在 `scripts/hooks/guard.mjs`，自测在 `scripts/validate-guard.mjs`（CI 与 pre-push 都跑）。
守卫管的不止冻结文件。要用就当场取，一条命令的事：

```bash
# 规则 id（两处来源：rules 对象的键 + fail() 里硬编码的。少查一处就会漏掉三条）
python3 -c "
import re
s=open('scripts/hooks/guard.mjs').read()
ids=set(re.findall(r\"fail\(\s*'([a-z0-9-]+)'\",s))|set(re.findall(r\"^  '([a-z0-9-]+)':\",s,re.M))
print('\n'.join(sorted(ids)));print('共',len(ids),'条')"

node scripts/validate-guard.mjs | tail -1   # 用例数
```

别用 `grep` 抓规则 id —— `fail(` 后面常换行，逐行匹配一条都取不到（空结果比错结果更难发现）。

> 2026-08-11 立此条：原文写着「规则清单以 guard.mjs 为准，本文件不留副本」，紧接着**自己抄了一份**
> —— 抄的那份漏了 `blind-tap-center`、`missing-team`、`archived-contract` 三条，用例数也停在 21（实为 28）。
> 有人照它写进对外文档，发现对不上才返工。写「以 X 为准」再抄一份 X，等于制造一个必然过期的第二源。

## 二、SessionStart：`session-context.mjs`

开场不用手查的那几条事实由它自动注入：
分支与脏文件数、未归档 OpenSpec 变更、后端契约可读性、pre-push 钩子装没装，以及
**有独有提交却长期没跟进的远端分支**（领先 main 且落后 >30）。
全绿时不输出 —— 每轮都响的提醒会被无视，报缺口才有信息量。
自测 `scripts/validate-session-context.mjs`（CI 与 pre-push 都跑，条数当场看输出别写在这）：
配齐的机器永远走不到告警分支，坏了只会安静地不再提醒。

> 最后那条 2026-08-15 立：08-12 主线从旧上游切过来时，一批在途 PR 被孤儿化 ——
> **分支还在 `origin` 上，但主线没有对应的 PR**。于是「已有在途 PR #24」这类记录集体作废，
> 而没人会发现：`BlindRunHistoryView` 因此在 review 里挂着「已实现」三天，
> 连上线前检查单都把它列进了演示视频「可以放心拍」。判活口径见 PR #27。
> 同一次删掉了这里原有的 `fork` remote / 双推两条告警 —— 08-12 已改口径，
> 而 `install-git-hooks.sh:233-237` 现在会主动清掉双推配置：照着那两条做会被安装脚本撤销。

## 三、Stop：`stop-checklist.mjs`（强制 commit / push）

**本轮写过的文件没提交**或**领先 origin** 时拦住本次停止并列出欠账。三条约束让它不至于变成噪音：

- `stop_hook_active` 兜底，一次停止只拦一次 —— 用户说「先不提交」时回一句说明再停即可，不会死循环
- 同一份欠账（相同路径集合 + 相同领先数）只提醒一次，签名存 `.git/aidrun-stop-checklist-seen`。
  别人没写完的脏文件长期躺着时不会每轮都叫；欠账内容变了才重新叫
- **欠账只算本轮 Edit/Write 写过的路径**（从 transcript 取，`scripts/hooks/transcript.mjs`）。
  并行会话或同事在改的脏文件降级为提示；调研落盘同理，会去**本轮会话内的所有分支**找提交，
  不只看工作树和 HEAD —— 单开 docs 分支提交调研是常态，只看 HEAD 会每轮误报一次

handoff **不作独立触发条件**，只在已有欠账时附带提醒 —— 纯客户端改动本就不该投递，
拿「提交晚于 handoff」当触发会让每次工具链提交都误报。什么该投递见记忆 `handoff-upkeep-workflow`。

自测 `scripts/validate-stop-checklist.mjs`（9 条，CI 与 pre-push 都跑）。
这条从「用户每轮口头提醒」升级成钩子，走的是 `AGENTS.md` §1.3。

## 四、PreToolUse / Bash：`shared-checkout-guard.mjs`

拦住不带显式路径的 `git commit --amend` / `git add -A` / `git commit -a` / `git stash` ——
**当且仅当**它们会捎带上本轮没碰过的文件。判据不是「命令危不危险」，
所以暂存区里全是自己写的东西时不会响。

理由是这个仓库的物理事实：**前后端两个工作区都可能有同事在同时编辑，而 `.git/index` 是共用的**
（记忆 `shared-checkout-concurrent-colleague-edits`）。同事跑一次 `git add`，
他的改动就在你的暂存区里；随后一个 `--amend` 把它们一并吞进你的提交。
2026-08-16 就这样把一笔编译不过的 WIP 推进了 PR，靠事后手动核对 `git show --stat` 才发现。

同一道守卫还拦「改写别人的历史」（amend / reset / rebase / branch -f 落在同事的分支上），
判据两条，2026-08-24 各修过一次误报，**改它之前先知道这两条为什么长这样**：

- **先判命令作用于哪个仓库**，再取 HEAD 与暂存区 —— 按 `git -C <path>` / `cd <path> &&` /
  钩子 payload 的 `cwd` 解析（Bash 的工作目录跨调用保留，可能早就不在本仓库了）。
  原先一律打在 `$CLAUDE_PROJECT_DIR` 上，于是在后端仓库跑 `git reset --keep` 被拦下、
  文案里印的却是 iOS 仓库的分支。**目标是别的仓库不等于放行** —— 后端也是共享 checkout，
  用它自己的 HEAD 判，拦截文案要指名那个仓库。
- **HEAD 在本会话开始之后被移动过**才拦（reflog 顶端 vs 会话起点）。原判据只有
  「本会话没切到过这条分支 + HEAD 提交不是本会话写的」，在**跨会话继续同一条分支**时恒为真，
  而那是本仓库最常见的干法。⚠️ 别改用「HEAD 作者 == `git config user.name`」当豁免：
  本仓库全部提交的 author 都是同一个人，**含事故里同事那条 `dd0d795`** —— 那条判据恒成立，
  等于把这一整条判据废掉，而且不会有任何东西提示它已经废了。

自测 `scripts/validate-shared-checkout-guard.mjs`（条数当场跑，别写在这里 —— 理由同第一节）。

## 五、PreToolUse + Stop：`research-log.mjs`（调研落盘）

PreToolUse 在联网工具调用前把 `docs/research/INDEX.md` 整份灌回给模型；
Stop 钩子发现本轮联网过但 `docs/research/` 一个字节没动就拦。
只是查一个 API 签名、不构成调研的，回一句说明再停。
自测 `scripts/validate-research-log.mjs`（CI 与 pre-push 都跑）。

> 位置约定本来就写在 skill `tech-decision-research` 里，但 skill 不被显式调用就不生效 ——
> 于是 `docs/research/` 建了两份报告却一直没有索引。这条是把约定接上强制。

## 六、成体系的 review 落哪（`AGENTS.md` §13 的完整版）

唯一位置 `docs/review/`，唯一索引 `docs/review/INDEX.md`，规则与调研同构：**开新 review 前整份读索引**，
按「复核触发条件」判旧结论作不作数；review 完落 `docs/review/{topic}-{YYYYMMDD}.md` 并回写索引一行。

与 `docs/research/` 的分工：research 记「外面是怎么做的」（联网事实，带来源与核实日期）；
review 记「我们做成了什么样」（对着代码与契约的判断，带 `文件:行号`）。
一次 review 引用一次 research 是常态，反过来不成立 —— 竞品事实不要写进 review，两处都写会漂移。

> ⚠️ 这条**没有 hook 强制**，`research-log.mjs` 只管联网调研。漏过第二次就按 §1.1 落成守卫。
>
> 2026-08-12 立此条：`frontend-backend-alignment-review-20260812.md` 原本躺在 `docs/` 根目录，
> 与 20 个同级文档混在一起 —— 下一次 review 既不会先读它，也不会挨着它落盘。已迁入 `docs/review/`。
