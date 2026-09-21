# 6 个「领先 main 却长期没跟进」的远端分支逐条判活（2026-09-21）

**范围**：SessionStart 钩子 `session-context.mjs` 报的 6 条远端分支（领先 main 且落后 >30）。
逐条判「该合、该重建、还是该判死」，并核实它们各自的前提在 main 上是否还成立。

**一句话结论**：**6 条分为三类，而分类的第一判据不是 diff 内容，是「它有没有开过 PR」** ——
4 条**从未开过任何 PR**（真孤儿，其中 3 条修的是 main 上至今仍然成立的错，已救回：PR #170 / #171），
2 条是 **PR 被静默关闭**（#108 / #109，同为 2026-09-05 关闭、**各 0 条评论、无任何理由记录**）。
🔴 **后者不能当孤儿处理** —— 有人做过决定，而理由查不到 ⇒ 重新合并等于推翻一个不知道内容的决定。
本轮因此先**停在判定**并问了项目负责人，**答复是「那两个关掉没关系」** ⇒ #108 的调研报告已合入（见 §4）。
附带查出一条独立成立的缺陷：**紧急联系人表单是全仓唯一没有焦点管理的多字段表单**（iPad 焦点问题未修，见 §3）。

> # 🔴 本报告第一版有一条硬错误，已订正：`/goal` 是**存在**的
>
> 第一版据 `claude-agent-view-for-cross-repo-20260919.md` §3 写下「`/goal` 死引用仍在全局
> `CLAUDE.md:16`」「PR #109 的 skill 里有一整节不存在命令的用法教程」——**两句都错**。
> 项目负责人当场指出「`/goal` 在 Claude 的 coding session 可以用」，随即核实：
> `https://code.claude.com/docs/en/goal` **HTTP 200**，16,657 字节，官方 **Automation** 分类，
> 标题逐字 "Keep Claude working toward a goal"。
>
> **这条错误的传播链，本身就是本报告主题的最好例子**（详见 §4.4）：
> 正确的官方 URL 一直写在 PR #108 那份报告的 §C.3 里 → 但 #108 被关闭、不在索引里 →
> 09-19 的调研读了索引没找到、重做一遍并得出相反结论 → **我今天引用它并放大**
> （据此说 PR #109 的 skill「把不存在的命令教进主线」，还建议项目负责人改掉全局配置里那条正确的规则）。
> ⇒ 一个被关掉的 PR 造成的损害不是「那份工作白做了」，是**它的正确结论缺席之后，后来的人会填进一个错的**。

---

## 0. 方法论：先查 PR 历史，再读 diff

**这是本轮最该记住的一条，因为我自己差点栽进去。**

上一轮（同日早些时候）判前三条分支时，`gh pr list --state all` 的过滤列表里**没有包含这三条**，
于是得出「从未开过 PR」的结论并直接救回。本轮把六条一起查，才发现其中两条是 **CLOSED 的 PR**。

```bash
# 判活的第一条命令，不是 git diff
gh pr list --repo Jayden23018/blind-run-ios --state all --limit 200 \
  --json number,state,headRefName,mergedAt
```

| 状态 | 含义 | 该怎么做 |
|---|---|---|
| **从未出现在列表里** | 真孤儿 —— 没人看过，没人决定过 | 读内容判活；修的错若在 main 上仍成立就救回 |
| **CLOSED 且 merged=false** | **有人主动关掉** | ⛔ **先查为什么关**。查不到就问，不要重新合 |
| OPEN | 在途 | 别另起分支做同一件事 |

⚠️ 本仓库一律 **squash 合并**，所以 `git branch --merged` 与 `git rev-list` 都会把已合并分支报成
「有独有提交」（记忆 `squash-merge-breaks-branch-merged-check`）—— 分支是否已落地只能看 PR 状态
或 `git diff --stat origin/main origin/<branch>`。

---

## 1. 判定总表

| 分支 | PR | 判定 | 一句话理由 |
|---|---|---|---|
| `docs/ai-ui-design-workflow` | **无** | ✅ 已救回 → PR #170 | 476 行调研，内容仍作数（仅 §2.4 Figma 需订正，已另落 09-21 报告） |
| `docs/ui-design-direction` | **无** | ✅ 已救回 → PR #170 | 修的三处错在 main 上**现在仍然成立**，见 §2 |
| `refactor/app-spacing-tokens` | **无** | ✅ 已救回 → PR #171 | 与 main 干净可合，但基点差 49 个提交 ⇒ 重建在 main 基点上 |
| `fix/ipad-form-keyboard-focus-20260905` | **无** | ⛔ **判死那 48 行**，但它指向的缺陷**未修** | 内容是自标「跑完就删」的诊断脚手架，见 §3 |
| `docs/opus5-workflow-research` | **#108 CLOSED** | ✅ **已合入**（项目负责人答「关掉没关系」） | 463 行报告，内容成立；§C.3 已 09-21 复核确认（`/goal` 存在）。只订正了两处「✅ 本轮完成」的未兑现宣称，见 §4 |
| `chore/slim-resident-context` | **#109 CLOSED** | ⛔ **实现判死、意图判活** | AGENTS.md 已分叉 13 次（510→283 vs main 501），机械应用会删掉一个月的新规则；单独取那个新 skill 会制造第二源。见 §5 |

两条 CLOSED 的 PR 都是 **2026-09-05T18:21:53Z 前后关闭、各 0 条评论**。
`gh pr view --json body` 里两份 body 都写得很完整（结论、数字、理由齐全）⇒ **不像是手滑开错**，
更像是关的时候有理由但没写下来。

---

## 2. 已救回的三条：它们修的错在 main 上仍然成立

这一节是 PR #170 / #171 的判活依据，逐条都在 `origin/main` 上当场核过：

| main 上的现状 | 核实方式 | 后果 |
|---|---|---|
| `blindRun/Core/DesignSystem/AppColors.swift` 的注释要求「先跑 `AppColorContrastTests`」，而**全仓不存在这个类型**；真实的 `blindRunTests/LowVisionChannelTests.swift` 就在 main 上 | `git ls-tree -r origin/main \| grep -i lowvision` 命中；类名零命中 | 照它去跑「找不到就跳过」—— 这行字在为一个不存在的检查背书（同型见记忆 `claimed-fallback-may-not-exist-in-release`） |
| `docs/ui/ui-review-checklist.md:36` 把「深色背景」列为 PR 必查项，而 `preferredColorScheme` 全仓 **0 命中** | `git show origin/main:... \| grep 深色` | 照 checklist 走的人会去实现一个从没存在过的强制深色 |
| `docs/ui/ui-handoff-ios.md:53` 仍写「接单后显示**完整**电话」 | 同上 | 与 `AGENTS.md` §8 自 2026-08-22（`f404de2` / 审计 F10）起的掩码口径直接冲突。那次同批改了 `technical-design-overview.md` 与 `user-manual.md`，**漏了这份** |

⚠️ **不做整文件覆盖**：`ui-handoff-ios.md` 的「危险操作」那行在 main 上已比分支版本更新
（09-16 加了「结束陪跑改为长按 2 秒」），整文件取分支版会把它删掉。只改该改的三行。

---

## 3. `fix/ipad-form-keyboard-focus-20260905`：脚手架判死，缺陷仍在

**分支内容**：单个 commit `2876a89`，仅 `blindRunUITests/blindRunUITests.swift` +48 行，
新增 `func testDIAGiPadRelationshipFieldFocus()`。它自己的文档注释第一句是：

> `/// 诊断用，跑完就删：iPad 上第三个输入框拿不到键盘焦点，量一下点击前后到底发生了什么。`

⇒ **判死那 48 行**。理由不是它没价值，是作者自己定义了它的生命周期：
合进主线等于把临时脚手架永久化，而它是 UI 测试（本仓库 CI 跑不了、只能真机，且两台设备现在离线）。
分支名是 `fix/` 但**一个 fix 都没有** —— 诊断写完，修复没写。

### 🔴 但它指向的缺陷没有被以任何方式修掉

`blindRun/Profile/EmergencyContactsView.swift`（672 行）的表单有三个输入框：

```
:564  TextField("联系人姓名", text: $name)
:568  TextField("11 位手机号", text: $phone)      .keyboardType(.numberPad)
:577  TextField("关系，选填，例如家人", text: $relationship)   ← 分支想诊断的「第三个输入框」
```

全文件 **0 处** `FocusState` / `.focused` / `submitLabel` / `onSubmit`。

而 `git grep -l FocusState origin/main -- 'blindRun/**/*.swift'` 命中 **9 个**文件
（`LoginView` / `BlindBookingView` / `BlindIntroCallView` / `BlindOrderStatusView` /
`BlindRunHistoryView` / `BlindRunnerHomeView` / `SafetyHubView` / `SupportTicketView` /
`VolunteerInviteSheet`）⇒ **紧急联系人表单是全仓唯一没有焦点管理的多字段表单。**

⚠️ **我没有在 iPad 上验过现象**，所以不断言「问题还在」。能断言的是：
**没有任何代码处理过这件事**，所以那个分支想诊断的东西不可能已被修好。

**为什么这条值得单独记**：紧急联系人是 SOS 链路的数据源
（`AGENTS.md` §6 的降级分支要拨「主紧急联系人」），而它是**盲人自己录入**的表单。
录不进去 = 求助降级时没有号码可拨。这不是排版问题。

**建议**（不在本 PR 做，需要真机先复现）：给那三个 `TextField` 加 `@FocusState` + `submitLabel`
串成链，然后在 iPad 上真机验一次。抓不成静态守卫 —— 「几个 `TextField` 才算需要焦点管理」
没有非任意的阈值，做成守卫的误报面会大于收益。

---

## 4. `docs/opus5-workflow-research`（PR #108 CLOSED）：已合入

**分支内容**：463 行调研报告 `docs/research/opus5-workflow-and-effort-20260906.md`
+ INDEX 一行 + 一个已过时的生成代码同步 commit（见 §6）。与 main 的唯一冲突是 INDEX 表格追加行。

**判定经过**：第一版停在判定（PR 被主动关闭且无理由记录）→ 项目负责人答**「那两个关掉没关系」**
⇒ 合入，只订正两处未兑现的宣称。合入时需要知道的三条：

1. **它的核心结论已经生效了，但走的是另一条路。** 报告 body 的三条（reviewer 指令不能写「只报高危」、
   Opus 5 effort 起点是 `high` 而非 `xhigh`、常驻上下文过长）**全部已在全局 `~/.claude/CLAUDE.md` 里**，
   而那里两处「依据见」指向的是**后端仓库**的姊妹篇
   `demo/docs/research/opus5-workflow-optimization-20260906.md`，不是这份。
   ⇒ 合这份的价值只剩「本仓库索引里能搜到」+ 它自称独有的那几块
   （`/effort` 优先级、`ultrathink` vs `ultracode` 原文、HN 45 条原始评论、本仓库常驻上下文实测）。
2. ✅ **§C.3（标题写着「本仓库最有增量的一条」）整节成立，09-21 已复核。**
   ~~第一版这里写的是「整节建立在一个不存在的命令上」，据 09-19 报告 §3 的「三处零命中」。~~
   **那是错的** —— `https://code.claude.com/docs/en/goal` HTTP 200、16,657 字节，
   官方 Automation 分类。报告里的命令写法、4,000 字符上限、met/impossible 裁决、
   「评估器不跑命令也不读文件」（逐字一致）全部对得上。

   ### 4.4 🔴 这条错误怎么产生的 —— 本报告主题的最好例子

   09-19 那份报告要找的官方 URL，**一直写在本报告 §C.3 的「来源」行里**。它没看见，因为：

   ```
   PR #108 被关闭 → 报告不在 origin/main → 不在 docs/research/INDEX.md
     → 09-19 照 AGENTS.md §12 第 1 条「开搜前整份读索引」读了索引，没找到
       → 重做同一个问题，得出相反结论
         → 我 09-21 引用它，并据此说 PR #109 的 skill「把不存在的命令教进主线」
           → 还建议项目负责人改掉全局配置里那条本来正确的规则
   ```

   ⇒ **一个被关掉的 PR 造成的损害不是「那份工作白做了」，是它的正确结论缺席之后，
   后来的人会填进一个错的，而且那个错的会进索引、被引用、被放大。**

   09-19 判错的方法论根因（值得单独记住）：三处核实**全都打不到内置斜杠命令这个类别** ——
   `/goal` 不是 skill、不以 `goal` 为文件名落盘、也不出现在 `claude --help`
   （`/clear`、`/compact`、`/effort` 同样都不在）。**三个打不到的地方零命中 = 零信息，
   但看起来像三重确认。** 而那份报告**自己的数据就自证了方法无效**：
   第一条写 `claude --help` 里 `grep -iE "goal|loop"` 零命中，第三条却写「skill 列表里**有** `loop`」
   —— 同一份报告里 `loop` 确实存在却也被那个 grep 判成零命中，那一刻就该推翻方法而不是推翻结论。
3. **它自己的进度表有两处未兑现的「✅ 本轮完成」**：第 #6 条写「`AGENTS.md` §9–§13 迁进 skill ✅ 本轮完成（PR #109）」
   —— 而 PR #109 被关闭了，main 上 `AGENTS.md` 是 501 行、`aidrun-hooks-and-guards` skill 不存在；
   第 #8 条写「真机测试用 `/goal` ✅ 本轮完成 —— 已写进 skill `aidrun-ship-check`」
   —— main 上那个 skill 里 `/goal` 零命中（它兑现在 PR #109 的分支上，而那个 PR 没合）。
   ⇒ **「✅ 本轮完成」在一份调研报告里指的是「我在某个分支上做了」，不等于「主线上有」。**

---

## 5. `chore/slim-resident-context`（PR #109 CLOSED）：意图仍成立，实现已不可用

**分支内容**：`AGENTS.md` 510 → **283** 行，理由与命令搬进两个 skill
（新建 `aidrun-hooks-and-guards` 125 行、扩充 `aidrun-ship-check` 110 → 233 行），
另改 `research-log.mjs` + 其自测。声称收益：常驻 53,890 字符 / ~21,556 tok → 41,099 / ~16,440（-23%）。

**意图判活**：目标本身站得住，而且有更新的依据 ——
[`claude-code-token-optimization-20260917.md`](../research/claude-code-token-optimization-20260917.md)
确认了「删它的理由是**窗口占用与信噪比**」（同时纠正了成本模型：cache read 只收标准价约 10%，
所以省的不是账单）。官方那句 "Bloated CLAUDE.md files cause Claude to ignore your actual instructions!" 仍然有效。

**实现判死**，三条各自独立充分：

1. **AGENTS.md 已分叉到不能机械应用。** 基点（`36b78e5`，2026-09-05）510 行 → 分支砍到 283 行；
   而 `origin/main` 现在 **501 行**，且基点之后 `AGENTS.md` 被改过 **13 次**
   （`git log --oneline <base>..origin/main -- AGENTS.md | wc -l`）。
   那 13 次里包含 09-16 的 SOS 改口径、09-18 的 `FlowInfoRow` 弹性视图那条、
   以及 09-21 新增的 `design-direction.md` 指路 15 行 ⇒ **照分支的 AGENTS.md 覆盖会删掉一个月的新规则。**
2. ~~🔴 它的 `aidrun-ship-check/SKILL.md` 带 3 处 `/goal` 死引用 ⇒ 合并它 = 把一个不存在的命令教进主线。~~
   ⛔ **这条理由作废（第一版的硬错误）** —— `/goal` 存在，见 §4.2 与 §4.4。
   那个 skill 的 `:159`「用 `/goal` 把「跑到绿」交给评估器」一整节
   （含 `:161` 评估器不跑命令的警告、`:165` 那条具体条件写法）**内容是对的，而且现在就该用**：

   ```
   /goal scripts/device-test.sh 的输出里 failed=0 且 passed>0，且我没有改动 blindRunTests/ 以外的文件
   ```

   ⇒ **这一节不但不是判死的理由，反而是本分支上最值得单独救回的东西**
   （它正好对上「零执行不是通过」那条纪律，见 `AGENTS.md` §11）。
   本轮没有救它，因为它的载体是那个会制造第二源的 skill 扩充（见下面第 3 条）；
   要用的话把这几行直接加进 main 上现有的 `aidrun-ship-check/SKILL.md` 即可，
   不需要连带那 123 行的搬迁。
3. **不能只取那个新 skill。** `aidrun-hooks-and-guards`（125 行纯新增、零冲突）看起来是最省的一半，
   但它的内容是从 AGENTS.md 搬出来的 —— AGENTS.md 不同步瘦身的话，那个 skill 就是**第二份副本**，
   正是 `AGENTS.md` §9 自己说的「写『以 X 为准』再抄一份 X，等于制造一个必然过期的第二源」。
   ⇒ 要么整套重做，要么不做。

**若要重做**（独立任务，不在本轮范围）：对当前 501 行重新做一次「规则留下、理由与命令搬走」，
并且**先把 `/goal` 那一节删掉**再搬。

---

## 6. 两条共同发现

**① `efbef3e`（生成代码同步：契约新增枚举值 `SCHEDULED_CONFIRMED`）已过时。**
它同时出现在 `chore/slim-resident-context` 与 `docs/opus5-workflow-research` 两条分支上
（说明二者从同一点切出）。`origin/main` 的 `Packages/AidRunAPI/Sources/AidRunAPI/Types.swift`
已有 **6 处** `SCHEDULED_CONFIRMED` ⇒ 那次同步早就以别的方式进了主线，重放它没有意义。

**② ~~`/goal` 死引用仍在全局 `~/.claude/CLAUDE.md:16`~~ → 整条作废，那一行是**对的**。**

第一版在这里写「唯一仍在误导的那一处在全局配置里，而它每个会话都注入」，并建议改掉它。
**那个建议是错的，已撤回。** 全局 `CLAUDE.md:16` 原文：

```
- 终态可验证的长任务用 `/goal <条件>` —— 每轮由独立 checker 验，满足才收工，不是给指令列表
```

逐句核对官方文档：「每轮」✓（"After each turn"）、「独立 checker」✓（"a small fast model checks"，
且官方特别说明 completion 由**另一个**模型判而不是干活的那个）、「满足才收工」✓、
「不是给指令列表」✓（官方 "Write an effective condition" 要求一个可测终态 + 说清怎么证明 + 边界约束）。
**那一行写得比官方摘要还准。** 唯一可补的是它没提 4,000 字符上限与 `or stop after 20 turns` 兜底。

⇒ 本轮对这条的净结果是：**订正了 09-19 的报告（§4.4），没有改任何配置。**

---

## 7. 反对意见

1. **「PR 被关就不要动」可能过度保守。** 如果 #108/#109 只是当时不想处理而顺手关的，
   那本轮的「停在判定」等于让 463 行调研继续躺着。**但代价不对称**：合错了是推翻一个不知内容的决定，
   停下来只是多花一次问答。选停。
2. **`fix/ipad` 那 48 行也许该合。** 如果接下来就要修那个焦点缺陷，诊断用例正好能复现。
   ⇒ 判死的是「作为长期用例合进 main」，不是「删掉别用」 —— 真要修的时候
   `git show origin/fix/ipad-form-keyboard-focus-20260905:blindRunUITests/blindRunUITests.swift` 随时取得回来。
   **分支不删**。
3. **本轮没有跑任何真机测试。** 两台设备 `devicectl` 实测 `transportType: None` /
   `tunnelState: unavailable`。§3 关于 iPad 焦点的全部结论都是**读代码得出的**，
   不包含「在 iPad 上实际是什么表现」。
