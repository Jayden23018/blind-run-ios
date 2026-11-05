# 大文件拆分与工作流耗时 / token 体检（2026-11-05）

范围：① 哪些长文件该拆；② 哪些测试或工作流程花时间、花 token，但作用不大。
上一份体检是 [workflow-audit-20261003.md](./workflow-audit-20261003.md)，本轮只补它没覆盖或已过期的部分。
所有数字都是当天现测，命令写在每节末尾。

## 一、现测数字

| 项 | 数值 | 来源 |
|---|---|---|
| CI 一次（`verify`，最近 60 次） | 成功的中位 **16.9 分钟**，p90 30.1 分钟（10-03 时 7.5–10 分钟） | `gh api actions/runs` |
| 其中「编译门禁」job | 中位 16.1 分钟；拆开看：`swift test` AidRunAPI **205–321 秒**，「重新生成 API 客户端并比对」**228–318 秒**，`build-for-testing` 374–587 秒 | 4 次成功 run 的 step 时间 |
| 上面两步的触发条件 | **无条件，每个 PR、每次 push 都跑**；而 pre-push 早已按路径分档（只改 `Packages/AidRunAPI/` 或生成脚本才跑） | `verify.yml:289-294` |
| 每天定时 run | 已有（`verify.yml:26-27`，北京时间 09:17），可承担「后端契约变了、生成代码过期」的探测 | 同上 |
| CI 失败 | 60 次里 19 次 failure；最近 30 次里 6 次失败都在「Checkout backend contract」—— `BACKEND_REPO_TOKEN` 11-04 到期 | job 明细 |
| 本地真机跑测 | 最近 36 个 result bundle：多数 1–7 分钟、1–59 条；6 个是 0 条（多半是中途掐掉）；1 个 29 分钟 | `$TMPDIR/aidrun-device-test-bundle*` |
| 近 14 天本仓库会话 | 499 个主会话；主会话缓存读 **30.9B token**、缓存写 591M、输出 107M | 会话 jsonl 的 `usage` |
| 工具结果字符量 | Read 26.6M、Bash 其他 16.7M、`sed -n` 8.9M、`grep` 5.4M、`device-test` 3.8M、`openspec` 2.1M | 同上 |
| 被 Read 最多的文件 | `BlindOrderStatusView.swift` **215 次 / 947K 字符**、`VolunteerOrderFlowViews.swift` 160 次 / 820K、`VolunteerHomeView.swift` 162 次 / 711K、`docs/research/INDEX.md` 41 次 / 579K、`BlindRunnerHomeView.swift` 97 次 / 532K、`BlindBookingView.swift` 127 次 / 519K | 同上 |
| 近 5 天 Read 次数 | `BlindOrderStatusView` 38、`BlindBookingView` 23、`VolunteerHomeView` 17、调研索引 15 | 同上 |
| 调研索引注入（`research-log.mjs`） | 每会话第一次联网注入 12,000 字符（约 1 万 token）。**索引 69 行按日期升序，截断后只剩 14 行，全是 08-05 至 08-21 的；09 月以后的 55 行一行都没注入** | `research-log.mjs:34,166` + 索引现算 |
| 调研 / review 索引行长 | 调研索引 135KB / 69 行，平均每行 1,036 字符、最长 3,839；review 索引最长一行 2,058 字符（「一句话结论」列实际是段落） | 同上 |

## 二、大文件：该拆的与不该拆的

判据（三条都看）：行数 × 近 45 天改动次数 × 近 14 天被 Read 的字符量。只大不常改的不急；常改又常被整读的先拆。

### 先拆（每个一个分支、一个 PR，互不碰同一文件）

| 文件 | 行数 | 45 天改动 | 结构 | 拆法 |
|---|---|---|---|---|
| `blindRun/BlindRunner/BlindOrderStatusView.swift` | 3,654 | 30 | 只有 2 个类型：ViewModel 1,941 行、View 1,705 行 | 按现有 MARK 拆成 `BlindOrderStatusViewModel+IntroCall`（:497）、`+MeetupPlan`（:68）、`+FixedPartner`（:1090）、`+MockCounterpart`（:1855）、`+Realtime`（:1907）；View 拆 `+LiveShare`（:3264）、`+SMSFallback`（:3291）和各状态区块 |
| `blindRunTests/blindRunTests.swift` | 7,286 | 16 | **1 个 XCTestCase 装了 309 条用例** | 按 MARK 拆成独立的 XCTestCase 子类（冷启动恢复、邀请卡补数、录音提示、终点保持、资质、Mock 对齐……）。好处不只是好读：`-only-testing` 能按类选，「只跑改动覆盖的用例」不必再逐条列方法名 |
| `blindRun/BlindRunner/BlindBookingView.swift` | 2,532 | 25 | View 1,475 行 + ViewModel 856 行 | ViewModel 移到独立文件；View 按表单段落拆 extension |
| `blindRun/Voice/VoiceOrderWizard.swift` | 1,407 | — | 1 个类型 1,380 行，已有 11 个 MARK | 按 MARK 拆 `+Asking`、`+Freeform`、`+DisambiguateStart`、`+Confirm`、`+Networking`、`+Transitions`、`+Commands` |
| `blindRun/Volunteer/VolunteerHomeView.swift` | 2,291 | 24 | ViewModel 主体 1,500 行 + 邀请队列 extension 507 行 | 拆 `+Dispatch`（:400）、`+InviteQueue`（:597、:1522）、`+DeclineUndo`（:1802） |

### 等在途 PR 合并后再拆

| 文件 | 原因 |
|---|---|
| `blindRun/Volunteer/VolunteerOrderFlowViews.swift`（3,503 行 / 45 天改 48 次 / 27 个类型） | PR #712 正在改它；现在拆必然冲突。合并后按类型拆：`VolunteerInServiceViewModel`（965）、`VolunteerInServiceView`（754）、`VolunteerOrderDetail*` 各一个文件 |
| `blindRunUITests/blindRunUITests.swift`（2,606 行） | 同上，#712 在改。`AccessibilityAuditTests` 已经按 `+主题` 拆了 25 个文件，照这个样子拆 |

### 第二批（中等收益）

`blindRun/Core/AppState.swift`（1,383，`AppState` 本体 1,223）、`blindRun/Core/AppRealtimeCoordinator.swift`（1,534）、`blindRun/Core/MockAPIClient.swift`（1,211，已有 `+Voice` `+IntroCall` 先例）、`blindRunTests/VoiceOrderWizardTests.swift`（2,991 / 114 条）、`blindRunTests/EmergencySOSTests.swift`（1,869）、`scripts/hooks/guard.mjs`（1,200 行，14 天被 Read 99 次 / 412K 字符，可按规则拆成模块）。

### 不拆

- `Packages/AidRunAPI/Sources/AidRunAPI/Types.swift`（36,992）与 `Client.swift`（9,510）：swift-openapi-generator 生成，文件头写着 do not modify。
- `OrderModels.swift`（46 个小类型）、`OrderDisplayHelpers.swift`（17 个）：已经是多个小类型，拆了只增加文件数。
- `docs/` 下的长文档：改动少，按需读即可。

### 拆分时的硬约束（每个拆分会话都要遵守）

1. **只搬代码，不改逻辑。** `@Published` 和存储属性必须留在主类型里；被别的文件用到的 `private` 改成 `internal`（不加 `public`）。
2. 新 `.swift` 不用改 `project.pbxproj`（见记忆 `ios-build-and-test-environment`）。
3. 搬 `accessibilityIdentifier` 字面量会被 identifier 守卫拦，用 Write 写新文件，别为误报改代码形状。
4. 判定通过的三条检查（见第四节）。

## 三、工作流：耗时或费 token 而作用不大的

| # | 问题 | 代价 | 建议 | 要不要负责人点头 |
|---|---|---|---|---|
| W1 | CI 每个 PR 都跑 `swift test` AidRunAPI + 重新生成并比对 | 每个 PR 多 **7.5–10 分钟** macOS 时长；后端先合语料或契约时，不相干的 iOS PR 也跟着红 | 两步加 step 级 `if`：只在 PR 改了 `Packages/AidRunAPI/**`、`scripts/generate-api-client.sh`、`scripts/openapi/**` 时跑；push 到 main 与每日定时照跑全量。必需检查名不变，不会卡合并 | **要**（放松门禁，分类器上次拦过同类） |
| W2 | 只改文档 / openspec / `.claude` 的 PR 也跑 16 分钟编译 | 每个文档 PR 16 分钟 | 10-03 已提过：specs job 判改动文件，build job 加 job 级 `if:`（job 级跳过算通过；workflow 级 `paths-ignore` 会让必需检查卡死，不能用） | **要** |
| W3 | 调研索引注入只给最旧的 14 行 | 每会话约 1 万 token，内容却是 08 月的旧结论，最新的 55 行看不到 | 改成注入表头 + **最近 N 行**（或每行只取「日期 + 问题」两列）；同时给索引行长立上限（「一句话结论」≤ 200 字，长内容进报告） | 不用（修钩子缺陷） |
| W4 | `BACKEND_REPO_TOKEN` 11-04 到期 | 最近 30 次 CI 里 6 次红在这一步，其余 PR 的契约门禁空转 | 你重新生成令牌填进仓库 secret（只能你做） | 只能你做 |
| W5 | 大文件被反复整读 | 6 个大 View 文件 14 天被 Read 约 3.9M 字符，占全部 Read 的 15%；`sed -n` 另有 8.9M | 由第二节的拆分解决；拆完后单文件 ≤ 800 行，改一个区块只读一个文件 | 拆分本身不用 |
| W6 | OpenSpec 变更积压 | 36 个未归档、「进行中」；14 天 `openspec-propose` 调 29 次，`openspec` 命令输出 2.1M 字符 | 建议先做一次清账（逐个判「已实现只差勾」还是「真没做」），再决定纯视觉改版要不要免提议。这是流程决定，本轮不动 | 要（流程规则） |

**查过、不是问题的**（防止下一轮重提）：

- 真机跑测本身：多数一次 1–7 分钟，已按改动范围跑，不是瓶颈。
- 钩子注入：`rtk` 改写的输出不进上下文；仓库内钩子都是「每会话一次」；codegraph 提示钩子 10-03 起只在带 `#cg` 时注入。
- 后端 `docs/handoff.md`：14 天里被读 109 次，但近 5 天 0 次，冻结已生效。
- ponytail 开场注入：近 48 小时 56 个会话里只剩 1 次，已基本停用。

## 四、怎么判定改对了（外部检验）

| 改动 | 通过条件 |
|---|---|
| 每个拆分 PR | ① CI「编译门禁」绿；② 拆分前后**非空行的多重集合相同**（只多出 `extension X {` / `}` / `import` 和访问级别改动），用 `scripts` 外的一次性脚本比对并贴结果；③ 测试文件拆分前后 `func test` 总数相等（例：`blindRunTests` 309 = 309）；④ 拆出的测试类在真机上按类跑一次，`passed=N failed=0` 且 N 等于该类方法数 |
| W1 / W2 | 合并后接下来 10 个不碰 AidRunAPI 的 PR，「编译门禁」中位 ≤ 9 分钟；每日定时 run 仍执行这两步（看 run 日志里 step 状态为 success 而不是 skipped） |
| W3 | 自测 `node scripts/validate-research-log.mjs` 新增用例：注入内容包含索引最后一行的日期；注入长度 ≤ 上限 |
| 整体 token | 两周后重跑本报告的统计脚本：大文件每次 Read 的平均字符数下降；调研索引注入里出现 11 月的行 |

## 五、复现命令

- CI 时长：`gh api "repos/Jayden23018/blind-run-ios/actions/runs?per_page=60"`，再对每个 run 取 `/jobs` 的 step 起止时间。
- 文件改动次数：`git log --since=45.days --format= --name-only origin/main | sort | uniq -c | sort -rn`。
- token 与 Read 统计：遍历 `~/.claude/projects/*blind-run-ios*/**/*.jsonl` 近 14 天文件，累加 `message.usage`，按 `tool_use_id` 把 `tool_result` 长度归到工具名和 `file_path`。
- 调研索引截断：取 `docs/research/INDEX.md` 前 12,000 字符，数其中以 `| 20` 开头的行。

## 六、任务拆分（2026-11-05 建）

负责人当天批准 W1、W2，W3 选「表头 + 最近 20 行」，拆分「有必要就全拆」。同一仓库同时最多 3 个任务，按下面顺序分批开：

| 批 | issue | 内容 |
|---|---|---|
| 1 | #714 | CI：包测试与生成比对按路径跑；纯文档 PR 跳过编译（先合，后面每个拆分 PR 都省时间） |
| 1 | #716 | 拆 `BlindOrderStatusView.swift` |
| 1 | #717 | 拆 `blindRunTests.swift` 成按主题的测试类 |
| 2 | #715 | 调研索引注入改为最近 20 行 |
| 2 | #718 | 拆 `BlindBookingView.swift` 与 `VoiceOrderWizard.swift` |
| 2 | #719 | 拆 `VolunteerHomeView.swift` |
| 3 | #720 | 拆 Core：`AppState` / `AppRealtimeCoordinator` / `MockAPIClient` |
| 3 | #721 | 拆 `VoiceOrderWizardTests` 与 `EmergencySOSTests` |
| 3 | #722 | 把 `guard.mjs` 按规则拆成模块 |
| 等 #712 | #723 | 拆 `VolunteerOrderFlowViews.swift` 与 `blindRunUITests.swift` |
