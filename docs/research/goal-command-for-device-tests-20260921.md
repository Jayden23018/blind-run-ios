# `/goal` 好不好用：机制、本机前提、社区评价，以及本仓库的三条特有风险（2026-09-21）

**问题**：`/goal` 到底好不好用？能不能拿它接本仓库的真机测试「跑到绿」？

**一句话结论**：**机制清楚、对本仓库这个场景确实对口，但有一条失控风险是本仓库必然撞上的**，
所以「条件里带 turn 上限」在这里是**必需项不是保险**。官方唯一的失控保护是
「连续几轮没有工具调用就停下」，而真机测试失败时**每一轮都真的跑了命令**⇒ **那条保护不会触发**；
而 `device-test.sh` 在设备离线/锁屏时是**快速失败**（先探活），于是
「快速失败 → 评估器判 not yet met → 再跑一轮」可以转得很快，而两台真机长期离线是本仓库的常态。
🔴 另外**本机 Claude Code 2.1.224 拿不到三个保护性特性**（check-in 需 2.1.234+、
idle check-in 需 2.1.236+、自动重试提示需 2.1.269+）。
⚠️ **社区评价不一致**，而唯一一条具体的负评描述的正是**假绿**形态 ⇒ `/goal` 报达成之后仍要自己看
result bundle 的 `passed=N failed=0`，**不能把它当成验证本身**。

---

## 1. 核实口径

- 官方文档自己抓原文：`curl -sL https://code.claude.com/docs/en/goal.md` → **16,657 字节**
  （HTML 版 `https://code.claude.com/docs/en/goal` → HTTP **200**）。全文读过，不经转述。
- 社区评价走 **HN Algolia API**（免 key 返回原始评论，记忆 `web-research-channel-routing`）：
  `query="/goal" claude code`、`tags=comment` → 660 命中，逐条读前 25 条。
- 本机实测：`claude --version` → **2.1.224**；三个 settings 文件的
  `disableAllHooks` / `allowManagedHooksOnly` / `CLAUDE_CODE_GOAL_CHECKIN_MINUTES` 全未设置；
  `scripts/hooks/stop-checklist.mjs` 逐行读过（229 行，`exit 2` + stderr，`stop_hook_active` 兜底）。
- ⚠️ **本轮没有真的跑过一次 `/goal`。** 斜杠命令是用户的输入通道，我发不出去 ⇒
  所有「跑起来会怎样」的结论都是**从官方文档 + 本仓库代码推出来的**，标注见 §6。

> 🔴 **本报告存在的前提是一条被订正的错误结论。** 同日早些时候
> [`claude-agent-view-for-cross-repo-20260919.md`](./claude-agent-view-for-cross-repo-20260919.md) §3
> 断言「`/goal` 不存在」，项目负责人当场指出「在 Claude 的 coding session 可以用」才纠正。
> 判错根因（三处核实全都打不到「内置斜杠命令」这个类别）见那份报告 §3 的订正块。

---

## 2. 机制（官方逐字，只记会影响用法的）

**它是什么**：`/goal` 是**一个 session 级的 prompt-based Stop hook 的 wrapper**（官方原话
*"a wrapper around a session-scoped prompt-based Stop hook"*）。每轮结束后把
「条件 + 到目前为止的对话」发给 small fast model（Claude API 上默认 Haiku），
返回三种裁决之一，各带一句理由：

| 裁决 | 行为 |
|---|---|
| **Not yet met** | Claude 继续下一轮，并**把那句理由当作下一轮的指引** |
| **Met** | 清掉 goal，transcript 里记一条 achieved |
| **Impossible** | 评估器判定条件永远无法满足 ⇒ 清掉 goal，记 failed + 理由。不用自己清 |

**三条选择判据**（官方给了 `/goal` vs `/loop` vs Stop hook 的对照表）：

- `/goal` —— 下一轮由**上一轮结束**触发，停在「评估器确认达成 / 判不可能 / 你 `/goal clear`」
- `/loop` —— 下一轮由**时间间隔**触发
- 自写 Stop hook —— 同样每轮触发，但**活在 settings 里对所有会话生效**，且可以跑脚本做确定性检查

⇒ 「终态可验证的长任务用 `/goal`」这个判据是对的（也正是全局 `CLAUDE.md:16` 写的那句）。

**条件怎么写**（这是全文最该照做的一段，官方 "Write an effective condition"）：

> *"The evaluator judges your condition against what Claude has surfaced in the conversation.
> **It doesn't run commands or read files independently**, so write the condition as something
> Claude's own output can demonstrate."*

三要素：**一个可测终态**（测试结果 / build exit code / 文件数 / 空队列）+ **说清怎么证明**
（如 `npm test` exits 0）+ **不许改的边界**。上限 **4,000 字符**。
可以写 `or stop after 20 turns` 兜底，Claude 每轮报告对该子句的进度、由评估器从对话里判。

**其他会用到的**：`/goal`（无参数）看状态（条件 / 已跑多久 / 评估过几轮 / 当前 token 花费 /
评估器最近一次的理由）；`/goal clear` 清掉（`stop`/`off`/`reset`/`none`/`cancel` 是别名，
`/clear` 也会顺手清掉）；`◎ /goal active` 是活跃指示器；Ctrl+O 看裁决理由。
**不改权限模式** —— 要无人值守得配合 auto mode，否则每个未预授权的工具调用照样问。

**成本**：评估跑在 small fast model 上，官方说 *"typically negligible compared to main-turn spend"*。
⚠️ 想换评估模型只有 `ANTHROPIC_DEFAULT_HAIKU_MODEL`，而官方警告它**不止影响 `/goal`** ——
`haiku` 别名和会话摘要等后台功能会一起跟着改。**不要为了 `/goal` 去动它。**

**失控保护只有一条**：
> *"If Claude keeps answering the evaluator without making progress (**no tool use for several turns
> in a row**), Claude Code stops the loop, prints a warning, and returns control to you with the goal still set."*

---

## 3. 🔴 本仓库必然撞上的那条风险：唯一的保护对我们不生效

把上面最后一条和本仓库的现实摆在一起：

```
保护触发条件：连续几轮「没有工具调用」
本仓库现实：  真机测试失败时，每一轮都真的调了 Bash 跑 device-test.sh
⇒ 保护不触发
```

再加一层：`scripts/device-test.sh` **先探活再跑**（设备离线 / 锁屏时立即失败，不是等超时），
所以失败是**快速**的。于是循环可以转得很快，而不是「每轮几分钟自然限速」。

而设备离线在本仓库是**常态不是异常** —— 记忆 `ui-test-runner-needs-usb-not-wifi` 记了 **11 种**
失败签名，其中大多数不是代码问题，要人去插 USB、点「信任证书」、开 UI 自动化开关，
或者等免费 profile 过期后重新登录 Apple ID。本轮写这份报告时两台设备就都是
`transportType: None` / `tunnelState: unavailable`。

⇒ **条件里必须带 `or stop after N turns`。** 这不是「保险起见」，是因为官方那条保护在这个场景下结构性失效。

**建议的条件**（已写进 skill `aidrun-ship-check` §6）：

```text
/goal scripts/device-test.sh 的输出里 failed=0 且 passed>0，且我没有改动 blindRunTests/ 以外的文件，or stop after 12 turns
```

`passed>0` 那半不能省 —— 它是本仓库「零执行不是通过」那条纪律
（`AGENTS.md` §11：`passed=0 failed=0` 一律当失败查）。少了它，**设备锁屏会被判成达成**。

---

## 4. 本机版本：三个保护性特性还没有

官方文档给了多个特性的版本下限，本机 `claude --version` = **2.1.224**：

| 特性 | 需要 | 本机 2.1.224 |
|---|---|---|
| check-in（后台任务卡住 30 分钟后主动介入，之后 1h → 每 2h 退避） | **2.1.234+** | ❌ 没有 |
| idle check-in（会话空闲时自己起一轮送 check-in，每次 prompt 间最多 3 次） | **2.1.236+** | ❌ 没有 |
| 自动重试提示（`Goal still active` / `Goal paused` 具名原因） | **2.1.269+** | ❌ 没有 |
| resume 时恢复 goal 覆盖 `claude --resume` 选择器 | 2.1.239+ | ❌ 没有（其余 resume 路径有） |

⇒ **后台任务卡住时不会有 check-in 来救**，只能自己看。这条与 §3 叠加：本机版本上 `/goal`
的自我纠错能力比文档描述的更弱，**turn 上限的必要性又高一档**。

> ⚠️ 顺带订正一条：`opus5-workflow-and-effort-20260906.md` §C.3 写了
> 「后台卡满 30 分钟触发 check-in，之后按 1h → 2h 退避」——那是**文档里的机制**，
> 而那份报告和本报告都在 **2.1.224** 上，**这个机制本机拿不到**。
> 报告没写错（它描述官方行为），但照它预期本机行为会等一个永远不来的 check-in。

**两个禁用开关**（官方：评估器属 hooks 系统，所以受 hooks 的信任规则约束）：
`disableAllHooks: true` 或 managed settings 里的 `allowManagedHooksOnly` 会让 `/goal` 整个不可用
（会明确告诉你原因，不会静默失效）。**本仓库 `.claude/settings.json` 与本机
`~/.claude/settings.json` 都没设这两项，实测确认** ⇒ 这条不挡我们。

---

## 5. 与本仓库 Stop 钩子的叠加：推断不冲突，但**未实测**

本仓库有自己的 Stop 钩子 `scripts/hooks/stop-checklist.mjs`（229 行）：
`exit 2` + stderr 阻止本次停止（Claude Code 把 stderr 回灌给模型），
`stop_hook_active` 兜底**一次停止只拦一次**（`:80`），所以它自己不会死循环。

官方对 `/goal` 与 hook 的关系说了两句：
1. `/goal` 自己**就是**一个 session 级的 prompt-based Stop hook；
2. Pause 的诱因里列了 *"a hook that ended the turn"*。

**推断**：两者方向一致（都是「别停，继续干」），且 `stop-checklist` 的 exit 2 是**阻止停止**
而不是**结束 turn**，所以不该触发那个 pause 分支。⚠️ **但这是推断不是实测**，
而且 opus5 报告 §445 早就把这条列为待验项（*"两者都在每轮结束后跑……理论上不冲突，但没验过"*），
到今天仍然没验。

**怎么验**（一次就够，谁先用谁验）：在有未提交改动的状态下设一个 goal ——
`stop-checklist` 一定会拦（它就是为「写过文件没提交」设计的）。看三件事：
① `/goal` 状态里的 turn 计数有没有正常增加；② 有没有出现 `Goal paused` 之类的提示；
③ stderr 那段欠账清单有没有被评估器当成「Claude 的输出」影响裁决（**这条最可能出问题** ——
评估器只看对话，而钩子回灌的 stderr 在对话里，它可能把「收尾没做完」读成「条件未达成的理由」）。

---

## 6. 社区评价：不一致，而唯一具体的负评正好撞上本仓库最怕的形态

HN Algolia，660 条命中里与 `/goal` 真正相关的四条：

| 作者 / 日期 | 逐字 | 判读 |
|---|---|---|
| `mohsen1` 2026-05-28 [48313546](https://news.ycombinator.com/item?id=48313546) | *"So far Codex /goal has been amazing but **Claude Code /goal or even /loop does not work hard enough and gives up. I have observed it just claiming it's 'iterating' in a broken loop or simply giving up.**"* | 🔴 **最该看的一条**。同一个人对比两个工具，点名 Claude Code 侧会「假装在迭代」或干脆放弃 |
| `redhale` 2026-05-27 [48293046](https://news.ycombinator.com/item?id=48293046) | *"for a while, Codex had `/goal` and Claude Code did not (though now Claude Code has it too)"* | 给上面那条定了时间坐标：**那是 Claude Code 刚跟上这个功能时的评价** |
| `MikhailTal` 2026-07-22 [49012794](https://news.ycombinator.com/item?id=49012794) | *"this is /goal in claude code/codex. also basically a slightly improved ralph loop"* | 中性。定位是「略微改进的 ralph loop」，不是什么新范式 |
| `mohsen1` 2026-05-19 [48189573](https://news.ycombinator.com/item?id=48189573) | 自述给每个 Codex 会话设一个 *"almost unachievable `/goal`"*，要求通过 PR 落到 main | 一种用法参考：把 goal 设得够大，让它一直有事做 |

**怎么用这条负评**：不是「所以别用」。它是 4 个月前、且针对的版本早于本机 2.1.224 的多次迭代。
但**它描述的失效形态是「假绿」** —— 「claiming it's iterating」正好是本仓库反复栽的那一类
（记忆 `merged-prs-whose-tests-never-ran`、`known-red-suites-hide-new-failures`、
`ui-test-launch-arg-typo-passes-silently` 全是同一家族）。

⇒ **纪律**：`/goal` 报「达成」之后，**仍然自己看 result bundle 的 `passed=N failed=0`**。
把它当成「省掉每轮敲回车」，不是「省掉验证」。这与 `AGENTS.md` §11 那条
「零执行不是通过」和 skill §1 的五步不冲突 —— `/goal` 换掉的是**触发方式**，不是**判据**。

---

## 7. 待实测的三条（本轮都没做，各自都便宜）

1. **`/goal` 在本机 2.1.224 + 桌面 App 里到底可用吗。** 官方明说支持 desktop app 与
   Remote Control，项目负责人也说「在 coding session 可以用」，但**我发不出斜杠命令**
   （那是用户的输入通道）⇒ 只能由用户验。判据：输入 `/goal` 无参数，看是否回状态或
   `No goal set`，而不是「未知命令」。
2. **与 `stop-checklist.mjs` 的叠加**，见 §5 的三个观察点。
3. **失控边界**：故意在设备离线时设一个真机测试 goal，看它在没有 turn 上限时转几轮才停
   （§3 的推断需要这个来证实或推翻）。⚠️ 这条会烧额度，**带上 `or stop after 3 turns` 再做**。

---

## 8. 反对意见

1. **这个场景也许根本不需要 `/goal`。** 真机测试失败的 11 种签名里**大多数要人动手**
   （插线、点信任、开自动化开关）—— 那些情况下无论转多少轮都不会变绿，
   `/goal` 的价值只体现在「失败是代码问题、而且能靠自己改对」的那一小部分。
   ⇒ 先按记忆 `ui-test-runner-needs-usb-not-wifi` 分诊，确认是代码问题再挂 goal。
2. **`or stop after N turns` 的 N 是拍的。** 12 轮没有依据，只是「够修几次编译错、
   又不至于烧穿额度」。第一次用完按实际观察调。
3. **本报告 60% 是官方文档转述 + 40% 是推断，0% 是实测。** §3 那条核心风险
   （保护不触发）是从两个事实推出来的，没有跑过一次循环去验证。按本仓库口径属「未证实」。
