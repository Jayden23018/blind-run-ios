# 并行会话改完要等合并才能上手机看、看到的是旧版、大字号挡视线（2026-11-06）

问题（负责人原话摘要）：并行开很多会话改 App，每个改完都要等 PR、核 PR、跑 `ship.sh`、合并，才能装到手机上看效果；有时会话在旧版本上加新功能，已删掉的功能又出现，界面乱；大字号下一直有 Mock 提示挡视野，大字号也不好用，但每次画面都是大字号。要官方推荐、社区做法和 App 开发流程。

负责人 11-06 的回答（AskUserQuestion）：

- 现在怎么看效果：**等合进 main 再装**。
- 大字号：**会话给的画面都是大字号**，且 **App 在大字号下本身难用**。
- 预览方式：选 **一个集成预览包**（不选每个 PR 一个 App、不选按 PR 号切换）。
- Mock 提示：**换成小版本标记**。

## 1. 等待卡在哪一步

不是 CI 慢。卡在「必须先合进 main 才能装到手机」。`ship.sh`（`~/.claude/scripts/ship.sh`）做 rebase → push → 开 PR → 交接闸 → 等 CI → 合并；CI 只有编译门禁与规格校验（`CLAUDE.md`：CI 跑不了 XCTest）。11-05 起会话不跑真机测试，负责人自己验（记忆 `owner-verifies-changes-no-device-tests`）。所以负责人看到效果的时间 = 会话做完 + 审 PR + 合并，合并是串行的。

## 2. 旧版本问题的根因：官方设计如此

Claude Code worktrees 官方文档（https://code.claude.com/docs/en/worktrees ，2026-11-06 读原文）：

- `worktree.baseRef` 默认 `"fresh"`：从远端默认分支（`main`）切出，**看不见任何未合并的 PR**。
- 另一个取值 `"head"`：从当前本地 `HEAD` 切。**不能设成分支名**。
- `--worktree #N` 或 PR 链接：从某个 PR 的 head 切。

09-28 调研（`parallel-session-duplicate-work-20260928.md`）已得出同一结论。推论：会话开得早，或「删功能」那个 PR 还没合，新会话的分支里就仍有那个功能；它截给你的图、你装的它的包，都是「旧 main + 它的改动」。`ship.sh` 合并前会 rebase，所以代码层面一般不会把删掉的东西加回来，但**合并前的一切画面都是旧底子**。

## 3. 官方怎么推荐

- 并行：每个会话一个 worktree，任务尽量不重叠；写和审分两个会话，审的用全新上下文（https://www.anthropic.com/engineering/claude-code-best-practices ；内置 `/code-review`）。
- 桌面版（https://code.claude.com/docs/en/desktop ）：Preview 只用于网页 dev server，**没有原生 App 预览**；PR 有 Auto-fix 与 Merge when ready（后者就是开 GitHub auto-merge，本仓库曾被分类器拦，见记忆 `parallel-sessions-issue-claim-and-auto-merge`）。
- **官方没有「合并前在真机上看几个 PR 合起来的效果」的功能。**

## 4. 最接近的官方机制：GitHub merge queue

GitHub 文档（https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue ）：merge queue 把「最新 base + 排在前面的 PR」合成临时分支 `gh-readonly-queue/{base}` 跑必需检查，某个 PR 失败就移出并重建后面的组。

不直接采用：我们的必需检查只能编译，验不了真机；而负责人要的是「看」，不是「检查通过」。**借它的做法放到本地**：本机合成「最新 main + 所有开着的 PR」，编译装到手机。

## 5. 社区做法

- 并行多了以后瓶颈是人的审阅和验证，不是写代码；实践上限约 3–5 个同时在途，判据是「每个 diff 等人看的时间在不在变长」（https://www.contextstudios.ai/blog/run-10-claude-code-agents-review-is-your-real-bottleneck 、https://crystl.dev/blog/how-many-agents-can-you-run/ ）。
- 临时集成分支：把几个 agent 分支合起来先整体编译，因为各自通过的改动合起来可能互相打架（https://dzone.com/articles/two-ai-coding-agents ）。
- 每个分支一个独立 App 并排装：不同 bundle id + App 名 + 图标角标（fastlane `badge` https://github.com/mathiasAichinger/badge 、`icon_versioning` 已 3 年无更新）。

以上是博客与讨论，等级低于官方文档，只当思路。

## 6. 大字号来源（本仓库实查）

- `blindRunUITests/AccessibilityAuditTests*.swift` 十余处带 `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL` 启动，且 UI 测试全部走进程内 Mock ⇒ 截图都是「最大字号 + 黄色 Mock 胶囊」。
- `blindRun/ContentView.swift`（Mock 横幅那段注释）早已写明：胶囊字号必须可缩放，所以 AX4/AX5 下会长到导航栏上，当时判「不发布、没有用例跑在 AX 档」没管 —— 后者已不成立。
- `ScreenTourTests` 不带字号参数，用手机自己的设置。

## 7. 采用的方案

1. `scripts/preview-build.sh`：固定的预览工作区里，`origin/main` + 全部开着的非草稿 PR（或指定 PR 号）逐个合并，冲突的跳过并报文件，编译装到 iPhone。用 `device-test.sh` 同一把设备锁。不改 main、不推送。
2. 包里写一个版本标记（Info.plist `AidRunBuildStamp`），Debug 包顶部显示「Mock · main@sha +#N」这类短标记，**替换**原黄色胶囊；字号是无障碍档时不显示。
3. 「App 在大字号下难用」另开 issue 做界面，不混进这次。
4. 流程：会话开 PR 后调度会话跑一次预览包，告诉负责人包含哪些 PR；会话给负责人的截图用默认字号，最大字号只留给攒批跑的审计。

## 8. 被否掉的方案

| 方案 | 为什么不用 |
|---|---|
| 每个 PR 一个独立 App 并排装 | 高德 key 绑 bundle id，要另申请 key；免费签名每台设备最多 3 个 App（UI 测试 runner 占一个），每 7 天 10 个 App ID（https://developer.apple.com/support/compare-memberships/ ）；负责人选了集成包 |
| 开 GitHub merge queue | 必需检查验不了真机；看效果的问题不解决 |
| `worktree.baseRef: "head"` | 只是从主 checkout 当前 HEAD 切，HEAD 上一样没有别人未合并的 PR；09-28 已否 |
| 按 PR 号一次装一个 | 看不到几个改动合起来的样子，「旧底子」问题照旧 |

## 9. 未查到

- GitHub merge queue 对个人账号公开仓库是否可用：文档首段没写，没继续查（方案不依赖它）。
- 社区里有没有现成的「本地合成多个 PR 并装到 iOS 真机」的脚本：没找到。
