# 工作流体检（2026-10-03）

范围：从「发现问题 / 提出功能」到「PR 合并」整条链路上，哪些步骤耗时、哪些钩子 / pre-push / CI 值不值得留。
任务单：Jayden23018/blind-run-ios#310。数据都是当天从 `gh` 与本机现测的。

## 一、现测数字

| 项 | 数值 | 来源 |
|---|---|---|
| 最近 30 个已合并 PR，从开到合的中位数 | **9.4 分钟**（全部 183 个中位 63 分钟，p90 71 小时） | `gh pr list --state all` |
| 当前开着的 PR | 3 个，全部是 DIRTY / UNKNOWN，挂了 6–12 天（#173 #181 #249） | 同上 |
| CI（verify）一次 | specs 36 秒 + build 6.5 分钟 ≈ 7.5–10 分钟；最近 40 次 38 成功 2 失败 | `gh api actions/runs` |
| **本地 pre-push 一次** | **2 分 43 秒**（main 上现测，rc=0）；内容是 CI specs job 的超集，CI 做同样的事只要 36 秒 | `time bash scripts/hooks/pre-push.sh` |
| 落后 main 的分支上 pre-push | 直接红：后端新增语料而本分支镜像没有（12 条「不在前端镜像里」），rebase 后才绿；而 PR 上的 CI 跑的是合并结果，不会红 | 本分支（落后 6）实测 |
| 远端分支 | 104 条；**88 条的 PR 已合并，其中 86 条分支尖 = 被合并 PR 的最后一个提交**（删了不丢任何东西） | `gh pr list` + `git for-each-ref` |
| 开场注入的陈旧分支清单 | 73 条 × 约 18 字符 ≈ 1.3k token，每个会话、每个 worktree 都注入 | `session-context.mjs` 的输出 |
| 近 30 天 309 个会话文件里 Skill 调用次数 | tech-decision-research 8、code-review 7、**aidrun-ship-check 6**、aidrun-a11y-voice 5、openspec-propose 4、aidrun-error-codes 2、aidrun-contract-sync 2；**openspec-apply-change / openspec-archive-change / aidrun-auth / swiftui-pro 0 次** | 会话 jsonl 统计 |

## 二、结论与已做的改动

1. **「并行会话互相等 PR」的主因已不是 PR 慢，而是「开了没人管」。**
   9 月 28 日起开了 auto-merge 后，新 PR 中位 9 分钟就合；剩下的是 3 个冲突后没人 rebase 的老 PR 和 86 条已合并却没删的分支。
   - 改动：全局 Stop 钩子 `~/.claude/hooks/inflight.py` 新增 `merge_gap`——分支已有**非草稿、未合并**的 PR 时，
     没开自动合并 → 提醒 `gh pr merge N --auto --squash`；DIRTY → 提醒 rebase；后端仓库（免费私有，不支持 auto-merge）→ 提醒「等 CI 再合」。
     草稿、已合并、已关闭都不吵。自测 `python3 ~/.claude/hooks/test-inflight.py`（新增 7 条断言，全过）。
2. **pre-push 与 CI 重复，且更慢。** 改为分档（`scripts/hooks/pre-push.sh`）：
   - 永远跑：openspec 校验、docs、读后端契约的 4 道门禁（几秒）。
   - 只在改了 `scripts/ .claude/ .github/` 时跑 11 个钩子自测；只在改了 `Packages/AidRunAPI/`、生成脚本时跑 `swift test` 与生成代码比对。
   - 取不到 diff 时按全量跑；`AIDRUN_PREPUSH_FULL=1 git push` 强制全量。
   - 实测：只改文档的分支 **2:43 → 3.7 秒**。`validate-prepush-contract-source.mjs` 9/9 通过
     （第一版漏了默认值，这个自测当场抓住：`RUN_CLIENT_CHECK: unbound variable`，已改为 `${RUN_CLIENT_CHECK:-1}`）。
   - 逐道耗时 ≥5 秒的会打印出来，下次想砍哪道一眼可见。
3. **会话开场的陈旧分支清单限长**（`session-context.mjs`，`STALE_LIST_LIMIT = 5`）：只列落后最多的 5 条，其余折成「另 N 条」。
   新增用例「超过上限只列前 5 条」，13/13 通过。真正的治本是删掉那 86 条已合并分支（见第四节）。
4. AGENTS.md §11 补了分档说明（一处，不另写副本）。

## 三、体检后**不动**的东西（和理由）

| 项 | 判断 |
|---|---|
| 仓库内 7 个钩子（guard / shared-checkout-guard / design-direction / openspec-reminder / research-log / session-context / stop-checklist） | **都留**。每个都对应过一次真实事故（AGENTS.md §1、§9、§10 有出处），Node 冷启动各约 50ms，不是时间瓶颈；非阻断提醒每会话只响一次。 |
| 11 个钩子自测在 CI 里每次跑 | 留。CI specs 总共 36 秒，不是瓶颈。 |
| AGENTS.md 49.7KB / 559 行，其中引用块（多是「某月某日改口径」的历史）占 13.7KB | **本轮不重写**。搜到的资料互相矛盾（Anthropic 文档建议 <200 行；一项实测称 25–500 行对遵守率无可测影响），而 09-17 的实测已确认缓存读只收 10%——省的主要是注意力，不是钱。重写 559 行契约文件的回归风险（`guard.mjs` 有 21 处引用它）大于收益。若要做：只把引用块里的「历史」搬去 `docs/review/`，规则句留原处。 |
| 全局 `~/.claude/CLAUDE.md` 25KB | 同上，不动。 |
| `skill-forced-eval.js`、`hooks.json.ecc-unused.bak`（60KB）等 `~/.claude/hooks` 里的死文件 | 没有任何 settings 引用它们，但我没有「没人再用」的证据，**未删**。 |

## 四、需要你来做的（被权限分类器拦下，我没有绕）

1. **删除 86 条已合并的远端分支**（分类器判 Git Destructive）。安全性已核：每条的分支尖都等于某个已合并 PR 的最后一个提交，
   `delete_branch_on_merge` 又是开着的，之后不会再积。名单与 sha 存在
   [`docs/review/merged-branches-20261003.txt`](./merged-branches-20261003.txt)（误删可按 sha 恢复）。命令：
   ```bash
   awk '{print $1}' docs/review/merged-branches-20261003.txt | xargs -n1 -I{} gh api -X DELETE repos/Jayden23018/blind-run-ios/git/refs/heads/{}
   ```
   另有 2 条不能删（合并后又推了新提交）：`chore/new-team-bundle-id`、`feat/volunteer-invite-sheet`。
2. **CI 对「只改文档 / openspec / .claude」的 PR 跳过 7 分钟 macOS 编译**（分类器判 CI Bypass）。做法：specs job 里判断 PR 改动文件，
   build job 加 job 级 `if:`；job 级跳过在必需检查里记为通过，但 workflow 级 `paths-ignore` 会让必需检查一直 pending 卡死合并，不能用。
   这属于放松门禁，需要你点头。
3. **3 个老 PR**（#173 #181 #249）冲突后没人管：是继续 rebase 还是关掉存档，由你定。
4. 启动时扫描报了：`~/.claude.json` 里有明文 API key 和 GitHub token（需**你本人**轮换）；几个 settings 文件权限 644。

## 五、观察到但不处理

- Skill 触发率低：`aidrun-ship-check` 本该每次收尾都用，近 30 天只有 6 次；`openspec-archive-change` 0 次，同时有 23 个未归档变更。
  说明「靠描述自动触发」不可靠——该用钩子的（收尾检查）已经在 `stop-checklist.mjs` 里；OpenSpec 积压是流程成本问题，值得你决定要不要对小改动免提议。
- `research-log.mjs` 在每次联网前注入约 12KB 的调研索引；本轮连着搜了两次，各注入一份。若觉得吵，改成每会话只注入一次。
