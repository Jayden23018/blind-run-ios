# 执行 prompt：把盲人端「陪跑进行中」的指标界面落地

设计定稿于 2026-09-15，完整规格见
`docs/research/blind-runner-ui-reference-study-20260915.md` §27 / §27.1 / §28 / §29。

---

## 复制以下全部内容作为新 session 的第一条消息

---

### 零、开工纪律（这几条比需求本身重要）

1. **设计已经定稿，不要重新设计。** 版式、间距、配色、VoiceOver 顺序都定完了，
   你的活是把它实现出来。对设计有意见先说，别边做边改。
2. **先进 plan mode 探索，别直接写码。** 这一屏的现状比需求复杂得多（见第二节）。
3. **改任何文件前，自己完整读一遍那个文件。** 探索可以外包，编辑不行。
4. **零执行不是通过。** `passed=0 failed=0` 一律当失败查。
5. **编译通过 ≠ 测试通过。永远不许把没执行过的测试写成通过。**

### 一、先读这些（按顺序，别跳）

1. `AGENTS.md` —— 最高优先级工作契约，尤其 §5（状态机）、§6（求助红线）、§11（验证命令）
2. `docs/research/blind-runner-ui-reference-study-20260915.md` 的 **§27、§27.1、§28、§29**
   —— 版式规格、留白规格、三条设计决定、本任务清单
3. `.claude/state.md` 顶部的「⏭ 下一件」小节 —— 与 §29 同内容，可当 checklist
4. skill `aidrun-a11y-voice` —— 盲人端 UI 与 VoiceOver 的硬规则

### 二、🔴 先搞清楚现状：这一屏不是空白页

**`BlindOrderStatusView`（`blindRun/BlindRunner/BlindOrderStatusView.swift:1016`）的 body 里
现在有 13 个 section 竖着堆：**

```swift
statusHeader(order)              introCallEntrySection(order)
volunteerCallSection(order)      inlineAskQuestionSection
keepWaitingSection(order)        actionSection(order)
runPlanShareSection(order)       dispatchAlgorithmNoticeSection(order)
peerMapSection(order)            lifecycleSection(order)
orderInfoSection(order)          statusLogSection
debugMockControls(order)
```

而 `docs/research/blind-ui-visual-benchmark-20260808.md` §1 规则 6 早就判过这一屏：
当时是 **7 个** section，结论是「进行中页面 = 一个身份 + 一个巨大动作」。
**现在是 13 个，不减反增。**

**开工第一件事（在 plan mode 里做完再动手）**：

> 确认 `IN_PROGRESS` 时这 13 个 section **实际渲染哪几个**。
> 它们多数是条件渲染的（`introCallEntrySection` / `keepWaitingSection` 显然不属于 IN_PROGRESS），
> 但**不要假设**，逐个读条件。把结论列出来给我看。

这一步决定了任务规模：如果 IN_PROGRESS 时只剩 3–4 个 section，那就是在它们之间插入指标区；
如果剩 8 个，那设计稿的「一屏四组内容 + 求助」和现状根本不是一回事，**先停下来问我**。

### 三、要做的四件事

#### 1. 接数据：`GET /api/orders/{orderId}/track`

已查清的前提（**别重查**）：

| 事实 | 出处 |
|---|---|
| `TrackStats` 已有 `distanceMeters` / `durationSeconds` / `avgPaceSecPerKm` | `blindRun/Core/Models/OrderTrackModels.swift:16-19` |
| 三者都有现成格式化属性 `distanceText` / `durationText` / `averagePaceText` | 同上 `:21-40` |
| 端点在 `IN_PROGRESS` 可调（`emptyStateText` 有 `.inProgress` 分支） | 同上 `:85-86` |
| 目前只接在回放页与完成页 | `OrderRouteReplayView.swift:143`、`CompletedTrackSummaryView.swift:47` |
| 陪跑中这屏**一个都没接**（`TrackStats` 等符号在该文件里 0 命中） | 已核实 |

⚠️ **轮询频率没定。** 订单详情已经 5 秒一轮，再加一个端点的频率是多少？
已在后端 `demo/docs/handoff.md` 问了，**先去看有没有答复**；没答复就先按 10 秒实现并在 PR 里说明。

#### 2. 按定稿版式渲染

```
陪跑中 · 张伟                    ● 定位正常
                                            ← Spacer
2.41                                        70pt 白 · tabular · 左对齐
总距离（公里）                                11pt #8A8A8F · 距上面 6pt
                                            ← Spacer
01:54            9'06"                      32pt 白 · 两列各占一半
总时长            实时配速                     11pt
                                            ← Spacer
[设置体重]                                   虚线框可点入口
消耗                                         11pt
                                            ← Spacer
──────────────────────────────
求助                                        100pt · #C81E14 · 贴边全宽
```

**排版原则：组内紧、组间松。** 数字与它的标签是一个语义单元（6pt），
四个单元之间才是留白 —— 用 `Spacer()` 自适应平分，**不要写死间距**
（写死在 SE 上会挤、Pro Max 上会散、AX 档下没法预先算）。

左右边距 **24pt**。求助块 **不参与平分**，固定贴底。

#### 3. 「设置体重」那一格

消耗千卡**算不出来**：后端零个体重字段（`bodyWeight` / `体重` / `身高` / `weightKg` /
`kg` / `热量` / `千卡` 七组词全 0 命中）。已投 handoff 问要不要加字段。

**在后端答复前**：那格做成「设置体重」的可点入口（虚线框），
`accessibilityLabel` 念「消耗，设置体重后可显示」，`accessibilityHint` 说明点了会去哪。

⛔ **绝对不许按默认体重估一个数显示。** 理由：视觉用户看到可疑数字会怀疑，
**听到一个数字的人只能相信**。给盲人一个他无法判断真假的数，比不给更糟。

如果后端已答复「不加字段」，那就整格删掉，只显示距离 / 时长 / 配速三项。

#### 4. 每公里播报

「已跑 3 公里」的播报触发点依赖这个数据源，一并接。
**不播配速、不播心率、不播卡路里。**

### 四、硬约束（违反会被守卫拦或造成线上缺陷）

- **主数字用白色，不用柠檬绿 `#D7FF3E`。** 柠檬绿是行动色，全 App 只有「能按的东西」是这个颜色。
  低视力用户正是靠它快速定位哪里能按。
- **数字全部 `monospacedDigit()`** —— 否则跑动中数字宽度跳变。
- **不加心率**（没有数据源）、**不加暂停按钮**（状态机里不存在 `PAUSED`）、
  **不加锁屏按钮**（会挡住求助）。
- **求助入口不许动。** `EmergencyActionSection` 在 `BlindOrderStatusView.swift:2156`
  的 `repeatStatusArea` 里。本轮**只做指标区**，求助的形态另有设计（报告 §23，未实现）。
- **「重复当前状态」按钮不能删**，序位钉死（WCAG 3.2.6）。
- **`IN_PROGRESS` 期间不得展示取消入口**（`AGENTS.md` §5）。
- 地图若在这一屏，保持 `accessibilityHidden` —— 且隐藏必须发生在元素被合成的那一层
  （`MapViewWrapper.isDecorative`），加在外层无效。

### 五、怎么用 subagent（这条按本仓库实测的判定表来）

**可以派：**
- 定位类（「某符号在哪」「谁调用了它」、跨 >2 文件的搜索）→ `model: haiku`
- 大文件摘要（`BlindOrderStatusView.swift` 两千多行，别整读进主上下文）
- **读已经跑完的测试日志**
- **视觉评审（见第六节，这是本轮的重点）**

**不许派：**
- ⛔ **写实现代码。** subagent 看不到项目全貌，出 bug 时完全瞎。
- ⛔ **跑测试。** 挂的时候你需要完整输出去诊断，它只会回「3 tests failed」。
  测试自己跑，**日志可以交给它读**。
- ⛔ 别起「资深 iOS 专家」这类人设 —— subagent 不增加能力只增加隔离，人设是纯噪音。

**派的时候 prompt 必须写死返回格式契约**：
> 返回 `文件路径:行号` + **原样粘贴**的代码片段。不要转述、不要总结设计意图、
> 不要建议改法。找不到就写「未找到」，不要猜。

并补齐它拿不到的前提：工作目录绝对路径、分支名、禁止清单（不许改文件 / 不许 git 操作）。

### 六、做完之后：视觉自检闭环（本轮新增，别省）

实现完成 ≠ 做完。**必须自己看一眼真实渲染结果，挑毛病，再回去改。**

#### 6.1 让截图拍得出来

盲人端陪跑中那屏**目前没有任何截图调用点**（现有 11 处集中在志愿者端 + 盲人首页 + 登录）。
你要加一条 UI 测试走到那一屏并 `attachScreenshot`。

启动到指定状态走 `launchApp(...)` 的 launch environment
（`blindRunUITests/blindRunUITests.swift:1299` 起），已有的键包括
`AIDRUN_UI_TEST_ACTIVE_ROLE` / `AIDRUN_UI_TEST_PRESEEDED_BLIND_PROFILE` /
`AIDRUN_UI_TEST_DISABLE_MAP` / `-UIPreferredContentSizeCategoryName` 等。

⚠️ **launch argument 打错名字会静默通过** —— UIKit 忽略未知值、App 以默认状态启动、
截图与默认那张逐像素相同、用例照报 `passed=1`。
**两次截图逐像素相同时先怀疑开关没生效**，别怀疑渲染逻辑。

#### 6.2 跑测试并导出截图

```bash
scripts/device-test.sh -only-testing:blindRunUITests/<你的用例>
```

`device-test.sh:224-242` 会**自动**导出附件到 `<result bundle 目录>/attachments`，
并打印个数与 `manifest.json` 路径（附件归属看 manifest 比看文件名可靠）。
导出失败不改变测试结论。

⚠️ **UI 测试构建永远没有高德 key**，地图一律是占位图 —— 别拿截图去验地图相关的东西。

#### 6.3 派一个**零上下文** subagent 做视觉评审

这一步的价值在于**它没参与设计，不会为自己的方案辩护**。
所以 **prompt 里不要写我们的设计意图、不要写规格数值**，只给图 + 通用质量标准。

建议的 subagent prompt（照抄，把路径换掉）：

> 你是一位移动端 UI 设计评审。看这几张 iOS App 的界面截图（绝对路径：`<...>`），
> 只回答一件事：**这个界面好不好看、干不干净、挤不挤。**
>
> 逐条挑毛病，每条给出：① 问题出在屏幕的哪个位置 ② 为什么是问题 ③ 具体怎么改
> （给方向和大致数值，如「这两组之间的间距应该再大一倍」）。
>
> 重点看：
> - 整体是否拥挤，留白够不够，视觉呼吸感
> - 对齐是否一致（有没有某个元素莫名其妙差几个像素）
> - 字号层级是否清楚（主次分明还是糊成一片）
> - 元素之间的间距是否有节奏（同组元素该近、不同组该远）
> - 有没有视觉上的孤儿（某个元素不知道属于哪一组）
> - 底部那块大色块的比例是否合适
>
> **不要夸。** 挑不出毛病就说「这一项没问题」，但先努力挑。
> 不要问我设计意图，就按你看到的判断。
> 不知道的不要猜，比如看不清的文字就说看不清。

**⚠️ 被要求找问题的 reviewer 一定能找出问题。** 照单全改会走向过度工程。
让它**全报**，你自己分两档：
- **A = 真的影响观感或可用性** → 改
- **B = 其余** → 默认不动，但记下来

#### 6.4 改完再跑一遍，直到 A 档清空

⚠️ **真机不在线就做不了这一步。** 两台设备（`111` / `iPad Pro (2)`）长期离线，
模拟器因高德无 arm64-sim slice **永久不可用**。
**这种情况下如实说「视觉自检未执行」，不要用 mockup 代替真实截图，不要说「应该没问题」。**

### 七、验证要求（`AGENTS.md` §11）

- 真机跑，CI 跑不了任何 XCTest
- **两台**：`111` 与 `iPad Pro (2)`。这是布局几何类改动，**单跑 iPhone 不算验过**
- 跑测试要显式传 `DEVELOPMENT_TEAM=ZW39BS8NXT`
- **第一个要看的**：AX5 大字号下四组内容会不会顶掉 `Spacer()` 的留白甚至溢出
  （`Spacer()` 平分在极端字号下会被压到 0，这是本设计已知的风险点）
- 默认只跑覆盖本次改动的 suite，不要裸跑全量（会超 Bash 600s 上限）

### 八、冻结与边界

- `Podfile` 整文件冻结
- `blindRun.xcodeproj/project.pbxproj` 行级冻结：不得触及 `DEVELOPMENT_TEAM`
- 任何构建相关文件不得写入 `EXCLUDED_ARCHS`
- **新增 `.swift` 文件不需要改 pbxproj**
- 本仓库只有 iOS 前端，不要加服务端代码

### 九、收尾（缺一件都不算做完）

1. 跑测试、贴**真实输出**（`passed=N failed=0`），没跑就明说没跑
2. 判断要不要同步 `demo/docs/handoff.md`（纯客户端改动不投递；
   若轮询频率或体重字段有了新结论，要回写）
3. `commit`：`type: 描述`，**不带 `Co-Authored-By`**
4. `push`

> Stop 钩子会强制第 3、4 步。用户明确说「先不提交」时回一句说明再停即可。
