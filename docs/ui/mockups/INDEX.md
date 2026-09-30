# 设计稿索引

**这份文件回答：哪一版设计是现行的、冲突时听谁的、实现落在哪、已知哪里没做到位。**
（`../design-direction.md` 回答「它该长什么样」，`../ui-handoff-ios.md` 回答「这页要有什么」，`../ui-review-checklist.md` 回答「改完查什么」，四份不重叠。）

## 为什么有这份文件

Claude Design 官方自认「没有版本历史」（[support.claude.com 原文](https://support.claude.com/en/articles/14604416-get-started-with-claude-design)，2026-09-30 核过）。设计包此前散在 `~/Downloads`、只有记忆知道该读哪份。依据与来源见
[`docs/research/design-versioning-and-impl-comparison-20260930.md`](../../research/design-versioning-and-impl-comparison-20260930.md)。

## 规则

1. **一个界面一行。** 新设计包放 `docs/ui/mockups/<主题>[-vN]/`，同 PR 在下表加一行；取代旧版时旧行状态改 `Superseded` 并写「被谁取代」，**不删**（旧版是新版 CHANGELOG 的基线）。
2. **状态只有三种**：`Current` 现行 · `Superseded` 已被取代 · `待确认`（证据互相矛盾，写清矛盾在哪，由项目负责人定）。**不许为了表格整齐把待确认写成 Current。**
3. **「决定源」写成文件路径**，不写「读记忆」。冲突时听它。与 `AGENTS.md` 冲突一律以 `AGENTS.md` 为准。
4. **实现后把偏差回写到「已知偏差」**，写「是设计要改还是代码要改」。设计与代码各自悄悄变，就是这份文件要防的漂移。
5. **入库只放 ≤1MB 的文件**（md、HTML 原型、关键 PNG）。PDF 与实现截图不入库，出处写在文末「未入库」。
6. **对照状态列**：没逐屏对照过就写「未逐屏对照」，不写「一致」。

## 索引

| 界面 | 目录 | 状态 | 取代关系 | 决定源（冲突听谁） | 实现落点 | 已知偏差 / 对照状态 |
|---|---|---|---|---|---|---|
| 陪跑员端 首页·准入·邀请卡 | `volunteer-home-accept-v3/` | Current | 其中「订单页」一节被下一行取代 | 包内 `陪跑员端首页与接单-设计交付文档-v3.md`；视觉基准 `storyboard-v3.html` | `VolunteerHomeView.swift` `VolunteerTabView.swift` `VolunteerInviteSheet.swift` `VolunteerInviteQueue.swift` | 已落地：#154 #157 #159 #161。未逐屏对照 |
| 陪跑员订单页 **v1**（邀请→约好→出发→汇合→完成） | `volunteer-order-page-v1/` | Superseded | 被 v2 取代 | — | 同下一行 | v1 已实现：#212 #216。⚠️ 这两条提交标题里的「订单页 v2」是**后端说明文件名**（`volunteer-order-page-v2-ios-handoff.md`），不是交付包 v2 —— 两套编号别混 |
| 陪跑员订单页 **v2** | `volunteer-order-page-v2/` | Current | 取代 v1；包内 `CHANGELOG-v1-to-v2.md` 逐项列差异 | **`DECISIONS-v2.md`**（V1–V18，负责人 09-26 逐条确认）＞ 包内其余 ＞ v3 规格 PDF ＞ 画板 px 值（见其 `README.md` 优先级）。设计画布在外部：`https://claude.ai/artifact/C9MMGSpVz9NtThjckXkUDV`，**不在仓库、不可版本化** | `VolunteerOrderFlowStep.swift` `VolunteerOrderFlowViews.swift` `VolunteerOrderFlowPage.swift` | 已落地：#229（FE-1）#232（FE-3）。**偏差**：① V13 要求「实现者同 PR 改 `design-direction.md`」，而 `docs/ui/design-direction.md:142` 仍写「不新增强调色」→ **文档要改**；② 后端依赖 BE-1/BE-2 的进度未核；未逐屏对照 |
| 陪跑员 **跑步中** | `volunteer-order-page-v2/08-running.md` + `reference/artboards/Run*.dc.html`；另见 `running-state/状态清单.md` 第 10–15 屏 | **待确认** | — | 见下方「冲突 1」 | `VolunteerOrderFlowPage.swift`（`VolunteerRunningPage`，:687）、`VolunteerOrderFlowViews.swift`（`VolunteerInServiceView`） | 三份材料互相矛盾，代码按其中一份做了。落地：#227（独立页，归档 OpenSpec `restyle-volunteer-running-page-v2`）+ #232（节奏/暂停/提示条）。**有意偏离画布**：头卡用藏青不用青绿（负责人 09-26 选定）、保留返回箭头、不标折返、无地图 |
| 盲人端 首页 + 单页订单流程 | `blind-order-flow/`（含 `PROMPT.md`） | Current | — | 包内 `PROMPT.md`；`design-reference/order-flow/home.html` 的数值为准 | `BlindRunnerHomeView.swift` `BlindOrderFlowView.swift` `BlindOrderFlowStep.swift` | 已落地：#141。**代码与文档里写的 `design-reference/order-flow/` 即 `docs/ui/mockups/blind-order-flow/design-reference/order-flow/`**（AGENTS.md:274、`docs/05-page-specs.md:177`、3 处 Swift 注释、2 处 UI 测试都用旧写法，此前仓库里没有这个目录）。未逐屏对照 |
| 盲人端 跑步中·异常与求助中心·深色·AX5（23 屏） | `running-state/`；另有 `blind-active-run-20260915/`（仅实现 prompt，设计规格在 `docs/research/blind-runner-ui-reference-study-20260915.md` §27–29） | Current（参考） | 两目录的先后关系**未核实** | 包内 `README.md`（其中「与现有实现的差异」一节）；README 自述**替换** `BlindActiveRunView` 内容区 | `BlindActiveRunView.swift` `SafetyHubView.swift` | 实现程度**未核**（README 说「跑步中不是新页面，而是订单页原地变形」，代码是否照此做未看）。未逐屏对照 |
| 锁屏实时活动 | `running-state/screens/D-锁屏实时活动.png`；`volunteer-order-page-v2/04-live-activity.md` | Current | v2 的出发/汇合卡在 v1 之外新增 | `DECISIONS-v2.md` V3 | `RunLiveActivityController.swift` `blindRunWidget/RunLiveActivityWidget.swift` `blindRunWidget/Shared/RunLiveActivityShared.swift` | 已落地：#146（跑者播报按钮 + 陪跑员只读卡）。**未落地**：出发/汇合卡（FE-2，PR #231 未合）；照包排版 268/242pt 超锁屏卡 160pt 上限（#231 单测 `sizeThatFits` 量得）；推送 token 拿不到（免费团队，issue #201），只能本地更新 |
| 跑后运动记录（两端） | `run-record/` | Current | — | **`DECISIONS.md` ＞ `HANDOFF.md`**。有意偏离 HANDOFF 的几处：坐标沿用 GCJ-02、高德不是 MapKit、服务时长从开始服务算、不显示「待确认」、两台手机各自计步 | `RunRecordHistoryView.swift` `RunRecordPresentation.swift` `RunRecordAudio.swift` `RunRecordService.swift` `VolunteerRunRecordView.swift` `RunnerRunRecordView.swift` | 分 8 阶段：阶段 2–6 已合（#189 #191 #194 #197 #203）；阶段 7 草稿 #249。各阶段真机截图（27MB）**未入库**，见文末 |
| 志愿者「我」首屏 | `volunteer-profile-first-screen-20260914/`（原有） | Current | — | 该目录 `README.md`（含每个字段的真实来源表） | `VolunteerProfileFirstScreen.swift` `VolunteerProfileFirstScreenView.swift` | 已落地：#136。未逐屏对照 |

## 冲突裁决

**冲突 1 · 陪跑员跑步中页**（状态「待确认」的原因）

| 来源 | 说法 |
|---|---|
| v2 画布 / `08-running.md` | 有暂停；结束陪跑是白色次要按钮；求助在右上胶囊；头卡青绿 |
| `running-state/`（《跑步中与跑后》） | **禁止暂停**；结束陪跑是黄色主按钮；求助是底部通栏 |
| `DECISIONS-v2.md` **V4** | 「App 内跑步中页面布局不动（深蓝三数字、长按 2 秒结束）」，新功能加进旧页 |
| 主线现状 | #227（09-27）已把跑步中换成独立新页（藏青头卡、右上求助胶囊、白色次要按钮长按结束），#232 再加节奏/暂停/提示条 |

**核实过的时间线**：V4 的审计基线是 `a8e77d4`（2026-09-26），它是 #227 的祖先提交 —— **V4 写于 #227 之前**，「布局不动」描述的是被 #227 换掉的旧页。所以 V4 与主线现状不一致，但**是不是该修订 V4、还是 #227 越过了决定，这是项目负责人的判断**，本索引不裁决。

**冲突 2 · 设计方向与状态色**：`DECISIONS-v2.md` V13 允许头卡与锁屏卡新增状态色，并要求同 PR 改 `../design-direction.md`；后者第 142 行仍写「不新增强调色」，第 88 行门槛也未提状态色。→ 文档要改（另开 PR，本 PR 不动方向文档）。

## 未入库（原件仍在 `~/Downloads`，本索引不删任何原件）

| 原件 | 为什么不入库 |
|---|---|
| `zhumangpao-handoff-v2/reference/v3-spec.pdf`（2.8MB，v1 包里的同名文件逐字节相同） | 体积；它是 09-18 由 `volunteer-home-accept-v3` 草图导出的订单页规格（首页 A5 · 邀请 B12 · 订单页 C5 · 取消迟到爽约 D），内容同 md |
| `zhumangpao-guide-handoff-v3/png/02-新邀请进来.png`（1.9MB） | 体积；`storyboard-v3.html` 可重新渲染 |
| `run-record-handoff/screenshots/stage3–6/`（74 张，约 27MB） | 这是**各阶段实现的真机截图**，不是设计稿；做「设计 vs 实现」对照时的实现侧素材，另行处理 |
| `zhumangpao-handoff (1).zip` | 与 `zhumangpao-handoff.zip` 逐字节相同（`cmp`），可删 |
| `zhumangpao-guide-storyboard-v3.html`、`陪跑员端首页与接单-设计交付文档-v3.md`、`助盲跑 跑后记录原型.html` | 各自与包内同名文件逐字节相同（`cmp`），可删 |
| `design_handoff_running_state/`（不带 2 的） | 与 `… 2/` 仅差一个 `给 Claude Code 的 prompt.md`；入库的是带 prompt 的那份 |
| `zhumangpao-continuous-order-flow(-v2).png`、`助盲跑 · 跑步中故事板与原型.pdf` | 故事板 / 原型的导出图，未核与入库包的对应关系 |
