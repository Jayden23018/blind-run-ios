# 安卓迁移指南：怎么参考 iOS 仓库里的设计稿、实现和截图

**读者**：在 `~/blind-run-andriod`（`Jayden23018/blind-run-android`）里做 iOS → Android 迁移的会话。
**这份文件回答**：哪些东西能直接拿来用、放在哪、哪份是现行的、没有的是什么、每个安卓 issue 该看 iOS 的哪几处。
（设计稿哪版现行以 [`mockups/INDEX.md`](./mockups/INDEX.md) 为准，本文件不留第二份状态表；本文件的「对应关系」是按标题和文件名对的，**没逐屏核**。）

状态：2026-10-04 草稿。凡写「未核」的是没验证的事实。

## 0. 先说三个会让迁移做偏的事实

1. **设计稿 PNG 是仅有的视觉基线，iOS 订单流没有集中存放的真机实现截图。** 盲人端订单流和陪跑员端订单流，仓库里只有设计稿，没有「iOS 实现长什么样」的截图（见 §3 缺口）。所以对照是「安卓截图 ↔ 设计稿 PNG」，不是「安卓 ↔ iOS 真机」。
2. **陪跑员「跑步中」页：现行的是 iOS 代码，不是设计画布。** 负责人 2026-09-30 裁决「保持主线现状」，画布有三处被有意偏离（保留返回箭头、不标折返、无地图），`DECISIONS-v2.md` 的 V4 已作废。照画布做会做错。见 `mockups/INDEX.md`「冲突裁决记录」。
3. **别照抄 iOS 的开发设施。** DEBUG 面板、进程内 Mock、`AIDRUN_UI_TEST_*` 启动变量、iPad 适配、Live Activity 的推送 token，都是 iOS 侧的东西，安卓没有对应物，也不需要。

## 1. 怎么读 iOS 仓库（必须照这个来）

- **读 `origin/main`，不读工作区。** iOS 的 `~/Downloads/blind-run-ios` 是共享 checkout，常停在别人的分支上、带别人没提交的改动。
  ```bash
  IOS=/Users/mac/Downloads/blind-run-ios
  git -C $IOS fetch -q origin main
  git -C $IOS show origin/main:docs/ui/mockups/INDEX.md          # 读文本
  mkdir -p /tmp/<本会话唯一目录> && git -C $IOS -c core.quotepath=false show origin/main:docs/ui/mockups/blind-order-flow/design-reference/order-flow/screens/01-home.png > /tmp/<本会话唯一目录>/01-home.png   # 取图片，再用 Read 看
  git -C $IOS ls-tree -r --name-only origin/main docs/ui/mockups  # 列文件
  ```
  路径里有中文时一定加 `-c core.quotepath=false`，否则路径带引号、取不到。
- **临时文件放 `/tmp/<本会话唯一目录>/`**，别用 `/tmp/x.png` 这类通用名（安卓 `CLAUDE.md` 已写过并行会话互相覆盖的事故）。
- iOS 的大文件（>500 行）不要整读：`codegraph node <符号>` 取函数体，或 `git show origin/main:<路径> | sed -n 'a,bp'`。

## 2. 设计稿清单（`docs/ui/mockups/`，在仓库里）

「状态」「决定源」直接抄自 `mockups/INDEX.md`（2026-10-04 读的）；冲突时听决定源，再听 iOS 的 `AGENTS.md`，状态为「待确认」的行**不许自己挑一份就做，先问**。

| 界面 | 目录 | 状态 | 决定源 | iOS 实现文件（看行为用） | 能直接看的素材 |
|---|---|---|---|---|---|
| 盲人端 首页 + 单页订单流程（匹配→约好→出发→汇合） | `blind-order-flow/` | Current | 包内 `PROMPT.md`；`design-reference/order-flow/home.html` 的数值为准 | `BlindRunnerHomeView.swift` `BlindOrderFlowView.swift` `BlindOrderFlowStep.swift` | `design-reference/order-flow/screens/01-home … 05-arrived.png`（5 张）、`storyboard.png` |
| 盲人端 跑步中 / 异常与求助中心 / 深色 / 最大字号 | `running-state/` | Current（参考） | 包内 `README.md`「与现有实现的差异」；实现程度**未核** | `BlindActiveRunView.swift` `SafetyHubView.swift` | `running-state/screens/` A 跑者端主故事板、B 异常与求助中心、D 锁屏实时活动、E 深色版、F 最大辅助功能字号（C 是陪跑员端，**不采用**） |
| 陪跑员 首页·准入·邀请卡 | `volunteer-home-accept-v3/` | Current | 包内 `陪跑员端首页与接单-设计交付文档-v3.md`；视觉基准 `storyboard-v3.html` | `VolunteerHomeView.swift` `VolunteerTabView.swift` `VolunteerInviteSheet.swift` `VolunteerInviteQueue.swift` | `png/` 下 4 张（决策摘要、首页准入接单、订单页全流程、取消迟到爽约） |
| 陪跑员订单页 v1 | `volunteer-order-page-v1/` | **Superseded** | — | 被 v2 取代 | 只有 HTML，**别照它做** |
| 陪跑员订单页 v2（邀请→约好→出发→汇合→完成） | `volunteer-order-page-v2/` | Current | **`DECISIONS-v2.md`**（V1–V19）＞ 包内其余 ＞ v3 规格 PDF ＞ 画板 px 值 | `VolunteerOrderFlowStep.swift` `VolunteerOrderFlowViews.swift` `VolunteerOrderFlowPage.swift` | **只有 HTML 画板**，13 张，见 §2.1 |
| 陪跑员 跑步中 | `volunteer-order-page-v2/08-running.md` + `reference/artboards/Run*.dc.html` | Current（以 iOS 现状为准） | 负责人 09-30：保持主线现状；V4 作废；头卡青绿（V19） | `VolunteerOrderFlowPage.swift` 里的 `VolunteerRunningPage`、`VolunteerOrderFlowViews.swift` 里的 `VolunteerInServiceView` | 画板仅作参考，**有意偏离** |
| 锁屏实时活动 | `running-state/screens/D-锁屏实时活动.png`；`volunteer-order-page-v2/04-live-activity.md` | Current | `DECISIONS-v2.md` V3 | `RunLiveActivityController.swift` `blindRunWidget/` | 安卓无对应物，对应的是前台服务通知 / 锁屏（**未核怎么映射，先问**） |
| 跑后运动记录（两端） | `run-record/` | Current | **`DECISIONS.md` ＞ `HANDOFF.md`**；有意偏离 HANDOFF：坐标沿用 GCJ-02、高德不是 MapKit、服务时长从开始服务算、不显示「待确认」、两台手机各自计步 | `RunRecordHistoryView.swift` `RunRecordPresentation.swift` `RunRecordService.swift` | `prototype.html`、`sample_run_record.json`、`sample_history.json`；真机截图见 §3 |
| 志愿者「我」首屏 | `volunteer-profile-first-screen-20260914/` | Current | 该目录 `README.md`（含字段真实来源表） | `VolunteerProfileFirstScreen.swift` `VolunteerProfileFirstScreenView.swift` | 3 个 HTML；README 里「累计里程后端刻意没有」已作废，主指标已换成累计公里（后端 `totalDistanceMeters`） |

另有跨界面的三份规则文档：`docs/ui/design-direction.md`（两端跟随系统明暗、配色只用 `AppColors`、不新增强调色、安全相关界面退回最克制一档）、`docs/ui/ui-handoff-ios.md`（每页要有什么，1882 行，按需取段）、`docs/ui/ui-review-checklist.md`（改完查什么）。

### 2.1 志愿者端画板怎么看（只有 HTML 的那批）

`volunteer-order-page-v2/reference/artboards/*.dc.html` 共 13 张：`Invite`（邀请）、`Main`（约好·前一晚）、`MainSoon`（约好·快出发）、`Depart`（出发）、`Meet`（汇合）、`Run` / `RunHelp` / `RunSignal` / `RunStates`（跑步中及其求助、慢一点、其他状态）、`LiveRun` / `LiveActivity`（锁屏卡）、`Done`（完成）、`Rope`（状态色与引导绳）。

- 它们依赖 `./support.js`，**这个文件不在仓库里**。已渲染好的 PNG（2x，390×844）在本机 `~/Downloads/aidrun-demo/design-png/volunteer/`（13 张）和 `…/blind/`（11 张），**不在仓库、只在这台机器上**。
- 自己重渲染：用 Chrome headless，`--window-size=390,844 --force-device-scale-factor=2 --virtual-time-budget=10000`，把 `~/Downloads/design_handoff_running_state/support.js` 放到画板同目录。字体来自 Google Fonts CDN，离线会回退。渲染细节与量化结果见 [`../research/real-device-demo-walkthrough-20260930.md`](../research/real-device-demo-walkthrough-20260930.md) §11。
- 画板源码里的 px 值**只作参考**，和文档冲突以文档为准（`volunteer-order-page-v2/README.md` 的优先级）。

## 3. 实现截图清单（能拿来对照的）与缺口

| 来源 | 内容 | 在哪 | 能不能用来对照安卓 |
|---|---|---|---|
| 跑后记录各阶段真机截图 | 74 张，`stage3`~`stage6`；命名如 `records-runner-light-top.png`、`records-volunteer-ax-xxxl-bottom.png`（两端 × 明 / 暗 / 最大字号 × 上 / 下） | `~/Downloads/run-record-handoff/screenshots/`（27MB，**不在仓库**） | **能**，是唯一成套的 iOS 真机实现截图，且覆盖明暗与最大字号 |
| 旧版（Flutter）截图 | 22 张：盲人端 12 张（首页、4 步预约、3 步匹配、接单、到达、完成评价）、陪跑员端 10 张 | 仓库 `docs/ui/legacy-screenshots/`（有 `00-index.md`） | **只能看当时的行为与流程，不是视觉基线**（它是被替换掉的旧版） |
| 竞品参考截图 | 115 张（aira-explorer、be-my-eyes、bemyguide、blindsquare、douya-kanjian 等） | 仓库里被 gitignore；iOS 工作区 `docs/ui/reference-screenshots/` 有本地副本；重抓脚本 `scripts/fetch-reference-screenshots.mjs` | 看别家怎么做，不是我们的目标 |
| iOS XCUITest 附件 | UI 测试里 33 处 `attachScreenshot(...)`（`blindRunUITests.swift` 20 + `AccessibilityAuditTests.swift` 13，2026-10-04 数的；`device-test.sh` 注释里写的「9 处」已过期） | 跑 `scripts/device-test.sh` 后导出到 `<result bundle 同级>/attachments`（含 `manifest.json`） | **现在机器上没有现成的 xcresult 包**；要新图得解锁 iPhone 重跑 |
| iOS 真机演示录屏（进行中） | 下单之后 12 步，两台真机 | 见 [`demo-run-of-show.md`](./demo-run-of-show.md)；录好后可抽帧 | **还没有**，录完才有 |
| 安卓自己的验收截图 | 设计系统 gallery（明 / 暗，1.0 / 2.0 字号）、按钮各状态、`regression-consent/contacts/login/settings`；滑块 `slider-79` | 安卓仓库 `docs/design-system-32/`、`docs/slider-79/` | 这是安卓一侧的基线，换页时对着它做回归 |

**缺口（没有就是没有，别编）**：盲人端首页和订单流、陪跑员端邀请 / 约好 / 出发 / 汇合 / 跑步中 / 完成，**没有集中的 iOS 真机实现截图**；`mockups/INDEX.md` 里这些界面「已知偏差」栏多为「未逐屏对照」，即 iOS 实现与设计稿是否一致本身没人核过。

## 4. 不依赖平台、可以直接复用的非视觉资产

| 资产 | 位置（iOS 仓库 origin/main） | 怎么用 |
|---|---|---|
| 订单状态机 | `AGENTS.md` §5；`docs/04-user-flows-and-state-machine.md`（427 行） | 11 个状态与流转表原样适用；**禁用旧词**（`submitted` `accepted` `matching` 等） |
| 真实响应样本 | `blindRunTests/Fixtures/*.json`，14 个（如 `BlindProfileResponse__self.json`） | 直接当 MockWebServer 的线上格式用例（安卓 `CLAUDE.md` 已要求「过 Retrofit 的类型必须有线上格式用例」） |
| 行为规格 | `openspec/specs/`（18 个能力）、`openspec/changes/archive/`（28 个已归档）、`openspec/changes/`（23 个**未归档、进行中**） | 先看已归档与 specs 里有没有同一能力；进行中的变更说明 iOS 还没定稿，别迁移半成品 |
| 领域词表 | `GLOSSARY.md` | 「注销」vs「删除账户」之类同义词；写下「iOS 没有这个功能」之前先查 |
| 规则技能 | `.claude/skills/aidrun-auth`、`aidrun-a11y-voice`、`aidrun-error-codes`、`aidrun-contract-sync`、`aidrun-ship-check` | 读 `SKILL.md` 当规则用；与 iOS 专有 API 相关的段落跳过 |
| 色值与间距 | `blindRun/Core/DesignSystem/AppColors.swift` `FlowPalette.swift` `AppSpacing.swift` `FlowMetrics.swift` | 安卓 `#32` 已经迁完并有 WCAG 对比度单测，**不要重做**；改任何取值先跑 `./gradlew testDebugUnitTest --tests 'com.jerry.aidrun.ui.*'` |
| 文案 | `SafetyModule.swift` 里的 `EmergencySafetyCopy`；`BlindOrderFlowStep.swift` 里的 `BlindRunCopy` | **求助二次确认文案逐字锁定**，见 `AGENTS.md` §6，原样搬 |
| 语音与错误码门禁 | `scripts/validate-golden-corpus.mjs`、`scripts/validate-voice-intent-words.mjs`、`scripts/validate-error-codes.mjs` | 读后端仓库做对撞；安卓已有 `scripts/validate-error-codes.py`，语音那两条安卓**还没有**（未核） |

⚠️ 两处文档与现实不符，别被带偏：
- `AGENTS.md` 写的 `docs/error-codes.json`（机器可读错误码表）在 `origin/main` 上**不存在**（2026-10-04 `git ls-tree` 查过）。错误码以后端 `ErrorCode.java` 为准。
- 安卓 `CLAUDE.md` 里「`docs/handoff.md` 记一笔」已过期：后端仓库 2026-09-24 起改用 GitHub Issues（`gh issue create --repo Jayden23018/blind-run-backend --label 待后端确认 --label handoff`）。后端地址 iOS 已改 `https`，安卓文档里还写 `http://`，且安卓 issue #20 正是明文传证件的问题。

## 5. 安卓 issue ↔ iOS 来源（按标题和文件名对的，未逐屏核）

| 安卓 issue | 该看的设计稿 | 该看的 iOS 实现 | 备注 |
|---|---|---|---|
| #34 盲人端首页与标签栏 | `blind-order-flow` 的 `01-home.png`、`home.html` | `BlindRunnerHomeView.swift` `BlindHomeCards.swift` | 求助条在「我的」tab 底部，不在首页（`AGENTS.md` §6，2026-09-16 起） |
| #35 #36 盲人端预约向导 | **没找到专门设计稿**（`blind-order-flow/PROMPT.md` 里可能有，未核） | `BlindBookingView.swift` | 下单规则全在 `AGENTS.md` §5：≥30 分钟、最远 7 天、≤300 分钟、夜间窗口 `[22:00,05:00)`、最多 3 张未完成预约 |
| #37 盲人端订单页（上）匹配→约好→出发→汇合 | `02-matching` `03-booked` `04-on-the-way` `05-arrived` | `BlindOrderFlowView.swift` `BlindOrderFlowStep.swift` `BlindOrderStatusView.swift`（约 3000 行，用 `codegraph node`） | 「约好」页同时覆盖 `SCHEDULED_CONFIRMED` 与 `PENDING_ACCEPT`（`BlindOrderFlowStep.swift:48`） |
| #39 倒计时与跑步中原地变形 | `running-state/screens/A`；README 说「跑步中是订单页原地变形」 | `BlindActiveRunView.swift` | 实现是否照此做**未核** |
| #40 完成幕与评价 | **没找到专门设计稿** | `BlindOrderStatusView.swift`（完成相关段） | 评价对象是「这次陪跑」不是给人打分，见 `docs/research/blind-runner-ui-reference-study-20260915.md` |
| #33 盲人资料页与引导流 | **没找到** | `blindRun/Profile/` | 视力状况需单独同意 |
| #42 志愿者派单邀请 | `Invite` 画板；`volunteer-home-accept-v3` | `VolunteerInviteSheet.swift` `VolunteerInviteQueue.swift` | 发 `ACCEPT` 还是 `INTERESTED` 只认推送里的 `requiresIntroCall`，客户端不自己算；两个方向的 409 都要兜（`AGENTS.md` §5） |
| #43 志愿者接单主页与临期确认 | `volunteer-home-accept-v3`；`Main` / `MainSoon` 画板 | `VolunteerHomeView.swift` | `confirm-departure` 与 `en-route` 不是一回事，别合并 |
| #44 #45 志愿者订单页 上 / 下 | `Depart` `Meet` `Run` `RunHelp` `RunSignal` `Done` | `VolunteerOrderFlowPage.swift` `VolunteerOrderFlowViews.swift` `VolunteerOrderFlowOutcomes.swift` | 跑步中以 iOS 现状为准（见 §0.2）；志愿者**没有**「误触」按钮（`AGENTS.md` §6） |
| #51 #52 通话磨合页（盲人 / 志愿者） | **没找到专门画板** | `BlindIntroCallView.swift` `VolunteerIntroCallView.swift` | 号码单向：盲人拿明文可直拨，志愿者只拿掩码，**掩码绝不能拼 `tel:`**；无声拒绝，客户端不许自己算轮次 |
| #61 跑后记录详情 | `run-record/DECISIONS.md` ＞ `HANDOFF.md`；`prototype.html` | `RunRecordHistoryView.swift` 等 | 截图见 §3 第一行；iOS 阶段 7 无障碍验收仍是草稿 PR |
| #12 无障碍验收与国产 ROM 保活 | `docs/09-accessibility-and-voice-guidelines.md`（334 行）；skill `aidrun-a11y-voice` | `AccessibilityAuditTests` | TalkBack 与 VoiceOver 焦点顺序、播报时机不同，必须真机逐页验（安卓 `CLAUDE.md` 已写） |

## 6. 每个页面的操作步骤

1. 读 `mockups/INDEX.md` 里这个界面那一行：状态是 `Current` / `Superseded` / `待确认`。`待确认` 先停下来问。
2. 读该行「决定源」指的文件，不读被标 Superseded 的包。
3. 看设计 PNG（§2、§2.1）。没有 PNG 的先按 §2.1 渲染。
4. 读 iOS 实现：只取需要的函数，不整读大文件。**行为以 iOS 代码为准的有两类**：跑步中页（§0.2），和 `AGENTS.md` 里写明的红线。
5. 用安卓已有的 `ui/components/`（`FlowCard` `FlowActionButton` `FlowStepper` `FlowInfoRow` `FlowAvatar` `FlowStatusCard` `OrderFlowScaffold`）实现，不新造 token、不新增强调色。
6. 无障碍：Compose 侧 `contentDescription` / `semantics` / `liveRegion`；iOS 的 `accessibilityLabel` 逐条对应，读屏会念的文案不要改。
7. 截图：明 / 暗各一张，再加最大字号一张（对应 iOS 的 AX5，安卓是系统字体缩放最大档），放进安卓仓库 `docs/` 下与 `design-system-32/` 同级的目录。
8. 对照分三层，**不做逐像素 diff**（跨渲染器必然全屏噪声，本仓库已验证）：① 数值对账（色值、字号、间距、最小触达，能脚本化的做成检查）；② 无障碍树 / TalkBack 朗读顺序；③ 安卓截图与设计 PNG **缩放到同宽并排**，只列「明显差异」并自分两档：A = 影响正确性或违反需求（必修）/ B = 其余（默认不动）。
9. 把偏差回写：建议安卓仓库也建一份同款「一个界面一行」的索引，写「是设计要改还是代码要改」。设计和代码各自悄悄变，就是索引要防的漂移。

## 7. 已知的跨平台差异（有依据的）

- **字体**：设计 PNG 与本机 Chrome 渲染同一份 HTML，字形略有差、内容区纵向累计漂移约 5pt（盲人端首页实测，见 `real-device-demo-walkthrough-20260930.md` §11）。iOS 真机用 PingFang SC，安卓用系统中文字体，**逐像素一致不可能**，别追。
- **没有 Dynamic Type / 有 `fontScale`**：字号一律 `sp`、不封顶（安卓 `CLAUDE.md` 已定）。
- **Live Activity ↔ 安卓**：没有一一对应；iOS 侧锁屏卡仅 `IN_PROGRESS` 才起、推送 token 在免费团队拿不到（issue #201）。安卓怎么映射**未核，先问负责人**。
- **高德**：安卓 SDK 是 `.jar`、只能用合并包 `3dmap-location-search`，x86 模拟器上地图不可用（安卓 `CLAUDE.md`）；iOS 侧是 CocoaPods，坐标一律单点转 GCJ-02。
- **后台定位 / 保活**：iOS 与安卓机制不同，国产 ROM 另有保活问题（安卓 #12），不要照搬 iOS 的做法。

## 8. 不要迁移的

DEBUG 面板与 `AIDRUN_UI_TEST_*` 启动变量、进程内 Mock、`blindRunTests` 的 XCTest 本身（用例想法可参考，代码不迁）、iPad 适配、`Xinghuo/`（星火同行地图，原型阶段）、`running-state/` 里陪跑员端 6 屏（已裁决不采用）、`volunteer-order-page-v1/`（Superseded）、`docs/_archive-*.bak`（已知有错，不得读取）。

## 9. 红线（两端相同，迁移时不得放松）

- **求助**：非 `IN_PROGRESS` 一律本地拨号（120 / 110 / 主联系人），**绝不调 `POST /api/emergency/trigger`**；云端 SOS 必须带新鲜真实 GCJ-02 坐标，拿不到就不发并且可见可听地告知；二次确认文案逐字锁定（`AGENTS.md` §6）。
- **永远不得宣称**短信已发出、已送达或联系人已被通知；字符串 `联系人已收到短信` 不得出现在发布产物中。
- **接单前**隐藏盲人联系方式、紧急联系人与敏感健康信息；自由文本一律接单后（`PENDING_INTRO_CALL` 对志愿者也不可见）。
- **全号只进 `tel:`**，不上屏、不进 `contentDescription`（读屏是外放的）。
- **枚举解码遇未知值不许整条崩**，降级到「未知」。
- **登出顺序**：先解绑推送 token，再调 `POST /api/auth/logout`。

## 10. 可以直接粘给安卓会话的启动提示

```text
处理 Jayden23018/blind-run-android 的 iOS→Android 迁移（先看开着的 issue，认领前 `gh pr list --search <编号> --state all` 查在途 PR）。

先读 iOS 仓库 origin/main 上的 docs/ui/android-migration-guide.md：
  git -C /Users/mac/Downloads/blind-run-ios fetch -q origin main
  git -C /Users/mac/Downloads/blind-run-ios show origin/main:docs/ui/android-migration-guide.md
它列了设计稿在哪、哪版现行、实现文件、可对照的截图与缺口、非视觉可复用资产、每个安卓 issue 对应的 iOS 来源。

硬规矩：
1. iOS 仓库一律读 origin/main，不读工作区；临时文件放 /tmp/<本会话唯一目录>/。
2. 实现某个界面前，先读 docs/ui/mockups/INDEX.md 里它那一行；状态「待确认」先问我，Superseded 的包不要读。
3. 陪跑员「跑步中」页以 iOS 代码为准，不是设计画布（负责人 2026-09-30 裁决）。
4. 求助二次确认文案逐字照搬，不得说「短信已发出 / 联系人已被通知」。
5. 对照不做逐像素 diff：数值对账 + TalkBack 朗读顺序 + 安卓截图与设计 PNG 并排，只列明显差异并分 A（必修）/ B（默认不动）两档。
6. 没有设计稿的页面（预约向导、完成幕、通话磨合）先问我，不要自己编视觉。
```
