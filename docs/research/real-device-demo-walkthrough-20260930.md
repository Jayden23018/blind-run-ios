# 真机演示 demo：「设计稿 | 真机实现」并排 + 界面流转，业界怎么做、我们缺什么

调研日期 2026-09-30 · 档位 **C（去掉学术线，三线并行）** · 三个 Sonnet subagent 合计约 43 万 token（12.4 + 12.3 + 18.2 万；事前估 25–35 万，超了）· 只读研究，未改任何代码。

**方法声明**：
- ① 官方/从业者线：`firecrawl_scrape` 返回 `Unauthorized: Invalid token`，拿不到任何原文，全部来自 WebSearch 摘要或 WebFetch 转述 ⇒ **该线没有 [高]，也没有原样引文**，用之前回原文再核。
- ② GitHub 线：star / push 日期 / license 来自 `gh api`，subagent 自述；口碑多为 README 自述。
- ③ 风险线：读的是本仓库代码与 `origin/main` 文档。**其中最关键的四处我自己复核过**（见 §2 末尾「主会话复核」），其余仍是 subagent 转述，行号落笔前请再核。

## 0. 与旧账的关系

| 旧报告 | 本轮 |
|---|---|
| [08-13 腾讯会议演示两台真机](./tencent-meeting-two-ios-device-demo-20260813.md) | 复核条件未触发，**直接沿用**：QuickTime 双窗口 + 腾讯会议 3.30+ 多选窗口 |
| [08-14 演示视频制作](./demo-video-production-20260814.md) | 复核条件未触发，**沿用**；本轮只补它没覆盖的「触点显示」「录屏是否带声」 |
| [09-30 设计稿版本管理](./design-versioning-and-impl-comparison-20260930.md) | **未推翻**；本轮是它的下游：版本索引已有，缺的是「怎么把它演示出来」 |

## 1. 一句话结论

**没有现成的东西可以直接用：官方没有「设计稿与实现并排展示」的推荐用法，开源里也没找到「导入截图 → 并排 → 点击流转」的成熟工具。但零件齐全**（截图导出、xcresult 渲染、触点叠加、真机录屏带声两条路），拼起来的活主要在「设计侧缺图」和「三类界面无法在 App 内复现」这两件事上，而不在工具上。

## 2. 本仓库现状（风险线读过的，不是估的）

- **Mock 只在 DEBUG 构建里能选**，Demo / Production 构建锁定 Demo Cloud。`blindRun/Core/EnvironmentConfig.swift`（`allows(_:)`：`.development` → `[.mock, .demoCloud]`；`.demo, .production` → 仅 `.demoCloud`）。⇒ **TestFlight / Release 包里没有「Mock 演示模式」，给别人手持体验只能走 Demo Cloud。**
- **Mock 能离线走完订单状态机**（`MockAPIClient.swift:524-559` 路由含 respond / intro-call / confirm-departure / en-route / arrived / start-service / finish / cancel）。但**盲人端是靠 DEBUG 面板手点推进**（`BlindOrderStatusView.swift` 有 5 处 `#if DEBUG`，其中 `:2995` 起的面板有「模拟志愿者接单 / 确认出发 / 到达 / 服务开始 / 服务完成」按钮），不是脚本驱动。
- **志愿者端邀请在 Mock 下没有推送**：`AppState.swift:945` `guard currentEnvironment != .mock,`；唯一入口是 DEBUG 启动变量 `AIDRUN_UI_TEST_SEED_INVITES`（`VolunteerHomeView.swift:284`）。位置互推、`ESCORT_*` 推送在 Mock 下无对应模拟。
- **预置数据**：`seedDemoData()`（`MockAPIClient.swift:992`）；`AIDRUN_UI_TEST_SEED_ORDER_STATUS` 可把订单钉在任意状态（`MockAPIClient.swift:1062`）；`MockAPIClient+RunRecord.swift` 可返回已完成订单的跑后记录；固定验证码 `000000`（`EnvironmentConfig.swift:79`）。启动变量共三十余个 `AIDRUN_UI_TEST_*`（`DISABLE_MAP`、`FORCE_DEMO_LOCATION`、`COLOR_SCHEME`、`SEED_HISTORY` 等）。
- **UI 用例没有从头走到 COMPLETED 的**：最接近的是 `testMockBlindRunnerBookingSmoke`（下单到匹配中）、`testMockVolunteerOrderFlowSmoke`（预置在途单）、`testMockVolunteerServiceArrivedWaitingScreenshots`（汇合等待截图）。
- **工程有 `DEMO` 编译条件**：`blindRun-Demo.xcscheme` 与 `DemoRelease` 配置存在（`project.pbxproj` 中 `SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEMO $(inherited)"` 出现 5 处）。但 `allows(_:)` 把 `.demo` 也锁在 Demo Cloud，**没有任何「Demo 通道 + Mock」的组合**。
- **设计侧素材**（`origin/main` 的 `docs/ui/mockups/`）：盲人端首页+订单流程有 5 张 PNG + storyboard；盲人端跑步中/求助/深色/AX5 有 6 张 PNG；锁屏实时活动有 1 张 PNG。**陪跑员订单页 v2 只有 HTML 画板**（`reference/artboards/*.dc.html`，无 PNG），其设计画布在外部 `claude.ai/artifact/...`，`INDEX.md` 自述「不在仓库、不可版本化」；**跑后记录只有 `prototype.html`**，实现截图 27MB 未入库。索引多行写「未逐屏对照」。
- **红线**（`origin/main:AGENTS.md`）：Mock「永远不足以作为发布签核依据」（`:129`）；非 `IN_PROGRESS` 一律本地拨号、绝不调 `POST /api/emergency/trigger`（`:253`）；不得宣称短信已发出（`:304`）；Mock / demo 坐标绝不上传（`:305`）；志愿者只拿掩码号、绝不拼 `tel:`（`:201`）。**演示 SOS 时 `SafetyModule.swift:757` 的 `dial` 会真的调 `UIApplication.shared.open`**，拦拨开关 `AIDRUN_UI_TEST_BLOCK_TEL_DIAL` 仅 DEBUG 生效。
- **设备**：`AGENTS.md:130` 2026-09-30 起上架包只支持 iPhone，发布验证只在 `111`；iPad 仍可当第二台开发机跑双机 E2E ⇒ 双机演示的第二台可以是 iPad，但它不代表上架形态。
- **音频**：当前代码**没有开启** voice processing（全仓搜不到 `VoiceProcessing`；录音会话 `.playAndRecord`，`SpeechInputService.swift:54-68`），所以 08-14 报告担心的那条**目前不一定触发**；**哪些界面录屏会丢声只能试拍 15 秒实测**，没有代码依据可判。
- **锁屏实时活动**：`pushType: nil`（`RunLiveActivityController.swift:160-163`）——本地更新可用、推送不可用（个人团队拿不到 `.token`，见记忆 `live-activity-push-token-needs-paid-team`）；仅 `IN_PROGRESS` 才起卡（`LiveEscortSessionCoordinator.swift:364`）；XCUITest 读不到锁屏卡；出发/汇合卡（PR #231）未合。**录屏能否录到锁屏卡：未找到资料。**

**主会话复核**（我自己读过源码）：`EnvironmentConfig.swift` 的 `allows(_:)`、`AppState.swift:945` 的 `guard currentEnvironment != .mock`、`VolunteerHomeView.swift:284` 的 `AIDRUN_UI_TEST_SEED_INVITES`、`origin/main:AGENTS.md:129-130` —— 与 subagent 所述一致。

## 3. 共识（多个来源一致）

**3.1 官方：没有「并排展示」的推荐，但给了可借的零件**
- Anthropic 官方页面里没看到「设计稿与实现并排展示 / 流程演示」的推荐用法。[Claude Design 帮助中心](https://support.claude.com/en/articles/14604416-get-started-with-claude-design) [中，仅指已读的官方页；claude.com 教程页只到 301，没读成]
- Claude Design 有 Export（.zip / PDF / PPTX / standalone HTML / Google Slides / Hand off to Claude Code）与 Share；同页写明没有版本历史。[同上] [中]
- Apple：带账号的 App 要提供有效 demo 账号或 "fully-featured demo mode"，后端保持在线；多角色账号写进 Notes。[App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) [中，搜索摘要，未读原文]
- Apple Tech Talk：过期/无效账号凭据在审核中很常见，好例子是数据充实、「像天天在用」的账号。[Tips for preventing common review issues](https://developer.apple.com/videos/play/tech-talks/10885/) [中]
- 系统录屏在控制中心，存入相册；录屏与屏幕镜像不能同时用。[Apple Support 102653](https://support.apple.com/en-us/102653) [中]

**3.2 触点显示：真机系统录屏和 QuickTime 都不画触点，只能 App 内叠加**
- 真机 iOS 没有内置 Show Touches；Simulator 有隐藏偏好，但 simctl 录不到触点（Apple 工程师 2020 年帖）。[Developer Forums 651405](https://developer.apple.com/forums/thread/651405) [中]
- Maestro 官方文章称 ShowTime 一类叠加需集成进 App，管不到系统界面。[Maestro blog](https://maestro.dev/blog/showing-tap-indicators-on-ios-recordings) [中]
- App 内叠加库（均 MIT）：[robb/visualizeTouches](https://github.com/robb/visualizeTouches)（132★，push 2026-04-09，SwiftUI modifier，录屏与 AirPlay 镜像时可见）；[jtrivedi/TouchInspector](https://github.com/jtrivedi/TouchInspector)（166★，2025-08-14）；[KaneCheshire/ShowTime](https://github.com/KaneCheshire/ShowTime)（577★，2023-04-20）；`morizotter/TouchVisualizer`（869★，**archived**）。[中，GitHub 原始数据 + README 自述]

**3.3 带声音的真机录制只有两条路，Appium 不带声**
- USB 的 QuickTime 协议：[danielpaulus/quicktime_video_hack](https://github.com/danielpaulus/quicktime_video_hack)（638★，MIT，README 称可抓 h264 + wav）。⚠️ **iOS 18 报告不可用**（[issue #159](https://github.com/danielpaulus/quicktime_video_hack/issues/159) 仍 open），代码实质更新止于 2022-08。[中]
- AirPlay 接收端：[FDH2/UxPlay](https://github.com/FDH2/UxPlay)（3118★，GPL-3.0，push 2026-09-30，镜像带 AAC，可转给 OBS）。**对 iOS 18/26 的实测口碑未找到**。[中]
- Appium 真机录屏无音频，音频要另录再合并（Appium 文档）。[高] [appium-xcuitest-driver](https://github.com/appium/appium-xcuitest-driver)（895★，Apache-2.0）

**3.4 「设计实现走查」的通行做法：Design QA，并排前先对齐条件**
- 术语 Design QA / design implementation review：设计师对照稿验收实现，问题回流修正。[Infinum handbook](https://infinum.com/handbook/devproc/day-to-day-work/design-implementation-checklist) [中]
- 并排前先对齐 viewport、状态、主题、设备密度、内容、交互状态；稿里没覆盖的空态单列为设计缺口。[OpenAI design-qa skill](https://mcpservers.org/agent-skills/openai/design-qa) [低，厂商 skill 说明；⚠️ 该站 Cloudflare 拦截，curl 返回 403 且页面标题是 Just a moment...，是反爬不是死链，但**主会话没能打开核对内容**，此条只当术语线索]
- 截图串成可点击流程的工具类目存在：UXPin 叫 screen-flow；Overflow、Storyflow、Marvel、Miro 可做。[Visily 综述](https://www.visily.ai/blog/best-user-flow-tools-and-apps) [低，厂商聚合，未逐个核]；开源侧只有 [penpot/penpot](https://github.com/penpot/penpot)（60528★，MPL-2.0，自带 prototype 热区，体量大）与 [drawd](https://github.com/codeflow-studio/drawd)（7★，2026-03 才创建）。[低–中]

**3.5 真机截图导出通道已有，且是真机可用**
- [ChargePoint/xcparse](https://github.com/ChargePoint/xcparse)（427★，MIT，从 xcresult 导出附件；**最后 push 2024-10-28**）、[XCTestHTMLReport](https://github.com/XCTestHTMLReport/XCTestHTMLReport)（772★，MIT，push 2026-09-28，把 xcresult 渲染成 HTML）。[中，GitHub 数据]
- 本仓库已有 `scripts/device-test.sh:288-289` 用 `xcresulttool export attachments` 导出（09-30 旧报告已核）⇒ **不必引入 xcparse**。

## 4. 争议（不与共识合并）

- **AssistiveTouch 能否让录屏显示触点**：techgrapple 文章称可以；[Apple Community 帖](https://discussions.apple.com/thread/255490166)称 iPadOS 18.4 上不显示；另有人用自定义手势或蓝牙鼠标指针绕。无定论。[低]
- **并排 vs 叠加（ghosting）**：[Thomas Essl](https://www.thomasessl.com/blog/qa-approach) 主张叠加优于并排（文章较旧）；OpenAI skill 主张并排同图输入。两者对象不同（人工验收 vs 模型判读），没有针对本场景的对比。[低]
- **qvh 在新系统是否可用**：README 称 macOS 上稳定；issue #159 报 iOS 18 失败。[中]
- **VoiceOver 演示谁来主持**：摘要作者建议「先演示坏的再演示好的、尽量请真实盲人操作，明眼人不熟练会低估线性导航的成本」——这是个人建议，不是 Apple 或机构定论。[低]
- **Maestro 真机**：Show HN（2025-12）称官方真机支持刚出，另有非官方 maestro-ios-device；上游 PR 状态以 09-30 旧报告为准（#3100 仍 open）。[低]

## 5. 没找到的（不用推测填）

- 「设计稿 | 真机实现」并排走查的成熟案例（含会议演讲、HN 帖）；开源的「导入截图 → 画热区 → 点击流程」成熟工具。
- Anthropic 官方关于「设计与实现并排展示 / 流程演示」的推荐；Apple 官方「真机 Show Touches」入口；Beta App Review 里 sign-in 字段的 Apple 原文（只有第三方摘要）。
- 盲人跑步 / 陪跑类 App 向公益机构演示的专门经验。
- fastlane snapshot 在真机上跑通的案例（fastlane 文档只写模拟器）。
- 录屏能否录到锁屏实时活动卡；UxPlay 对 iOS 18/26 的实测；Fingertips 仓库地址（两次 404）。
- 所有 firecrawl 原文（工具失败，见方法声明）；HN Algolia 一次抓取失败。

## 6. 三种交付形态的阻断项（有依据的才列）

**(a) App 内演示模式（Mock + 脚本）**
- Mock 仅 DEBUG 可选 ⇒ 要在 Release / TestFlight 包里提供，得新增「演示通道 + Mock」的组合，`AppBuildChannel.allows(_:)` 这一道闸就要改；这属于**行为变更**，按 `AGENTS.md` §10 须先有 OpenSpec 变更，且 Mock「永远不足以作为发布签核依据」（`:129`）与「Demo 与 Production 构建锁定 Demo Cloud」（§8）都要重新表态。
- 志愿者派单与位置互推在 Mock 下无 WebSocket；盲人端推进靠 DEBUG 面板手点。要做到「一键走完整流程」需新写脚本层。
- 锁屏卡依赖真实进入 `IN_PROGRESS` 的会话，Mock 复现不了。

**(b) 真机录屏成片**
- 语音下单界面是否丢声要先试拍；触点要 App 内叠加（DEBUG 叠加库不能带进 Release）。
- 锁屏卡能否入镜无依据。
- SOS 演示不能触发真实拨号（拦拨开关仅 DEBUG）；云端链路仅 `IN_PROGRESS` 且要真实 GCJ-02 坐标。
- 改一处界面就要重录。

**(c) 可点击网页（真机截图串联）**
- 陪跑员端、跑后记录没有可并排的设计 PNG（只有 HTML）；陪跑员订单页 v2 画布在仓库外。
- 索引多行「未逐屏对照」——并排一摆出来，对照结果会**当场变成对外展示的偏差清单**。
- 出发/汇合锁屏卡（PR #231）未合。
- 网页只能展示静态截图，展示不了语音播报与锁屏卡的动态。

## 7. 反对意见（什么情况下上面的判断是错的）

1. **「没有成熟工具」可能只是没搜到。** 官方线全程无原文（firecrawl 失效）、HN 抓取失败、Reddit 未专门搜；「设计稿并排走查」的中文语境和公司内部流程几乎不会公开。用「没找到」推出「没人做」是我不该下的结论，只能说「本轮没找到」。
2. **做成 (a) 的阻断项可能被夸大。** 如果目标观众是「团队 / 合作方」，直接用 DEBUG 构建装到你自己的真机上现场演，Mock 的 DEBUG 限制根本不构成阻断（这正是 Mock 现在的用法）；阻断只出现在「把包交给别人自己拿去用」这一步。
3. **设计稿缺图未必是问题。** 陪跑员端只有 HTML 画板，用无头浏览器渲染即可得到 PNG；真正的问题是渲染结果与 claude.ai 画布是否一致，这一点本轮**没有验证**。
4. **线 1 的 [中]/[低] 占比高，且含厂商自述**（Visily、OpenAI skill 说明、Percy 类），不该拿来当「业界共识」的依据，只能当术语线索。

## 8. 对本仓库的含义（建议，非已执行；带我的推断）

以下是**推断**，不是来源原话：
- 零件够、成品缺 ⇒ 最省的路是**「(c) 网页做骨架 + (b) 录屏片段补动态 + 现场用 Demo Cloud 双机联动」的混合**：网页负责「设计 | 实现」并排与流转（可发链接、可复盘、支撑你要的「专业、可给别人看」）；语音、锁屏卡、SOS 这三类 (c) 覆盖不了的用短录屏补；现场手持演示走 Demo Cloud，因为**志愿者派单在 Mock 下没有推送，唯一无需 DEBUG 种子的路径就是真 WebSocket 双机**（`scripts/dual-device-validation.sh` 已有雏形）。
- **暂不建议做 (a)**：要改 `allows(_:)` 闸、走 OpenSpec、重新过一遍「Mock 不能当签核依据」的表态，改动面大于收益；若只是自己现场演，DEBUG 构建 + `SEED_*` 启动变量已够。
- 下一步要先做的两个**便宜的验证**（各 <30 分钟，且能推翻上面的建议）：①真机试拍 15 秒语音下单，回放确认有没有声音；②用无头浏览器把陪跑员订单页 v2 与跑后记录的 HTML 渲染成 PNG，肉眼比对与 claude.ai 画布是否一致。

## 9. URL 核验

2026-09-30 对报告内 22 个 URL 跑 `curl -sIL`：21 个 200；`mcpservers.org` 返回 403（换 UA 的 GET 仍 403，页面标题 `Just a moment...` ⇒ Cloudflare 反爬，非死链），内容未核，已在 §3.4 标注。

## 10. 复核触发条件

Anthropic 发布「设计稿与实现并排 / 走查」的官方用法；firecrawl 恢复后重抓线 1 的官方原文；`quicktime_video_hack` #159 关闭或 UxPlay 出现 iOS 26 实测；本仓库 `AppBuildChannel.allows(_:)` 改动或出现「演示通道 + Mock」；PR #231（出发/汇合锁屏卡）合并；陪跑员端 / 跑后记录补齐设计 PNG。
