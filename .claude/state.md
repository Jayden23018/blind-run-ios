# STATE — 跑步中与跑后（汇合 → 跑步中 → 跑后）2026-09-16

分支 `feat/blind-run-running-state`（从 `main@d8b6307` 开出，**上一轮的 PR #141 已 squash 合入**）

设计交接包在 `/Users/mac/Downloads/design_handoff_running_state 2/`：

- `状态清单.md` —— **唯一权威的逐屏规格**，23 个画面 × 5 项（界面元素 / VoiceOver 标签 / 播报文案 / 触发条件 / 播报优先级）
- `README.md` —— 总规格、动效参数、token 表、**映射到本仓库哪个现成实现**的表
- `screens/*.png` —— 六组位图，**像素基准**（A 组前三屏要逐像素一致）
- `助盲跑 · 跑步中故事板与原型.dc.html` —— 浏览器打开可点，**验播报队列规则用它比读文字快**

---

## 一、已拍板（项目负责人 2026-09-16 确认，**不要重新讨论**）

1. **跑步中那屏按新设计重写，但保留三件**。
   现有 `BlindActiveRunView`（2026-09-15 产品定稿）是深底白字执行屏，与新设计（浅底白卡、
   居中 82pt、黄色主按钮 + 浅红求助）正面冲突，差一天。按**新设计**做，保留：
   - ① 顶行的定位新鲜度那一行 —— 不开读屏的低视力用户唯一能**看见**的 GPS 提示。
     新设计只给「按播报时追加一句」，那条通道对他们等于不存在。
   - ② 求助失败 / 撤销求助那几个条件按钮（`BlindActiveRunSafetyAnchor:236-257`）——
     删了就等于「云端求助失败后屏幕上没有任何能按的东西」，只剩一句 TTS。
   - ③ 「重复当前状态」—— 见下一条。
2. **「重复当前状态」保留导航栏右侧那枚图标**（①②④ 三屏），③ 由「播报当前数据」承担。
   新设计稿这三屏的导航栏右侧是空的，**这是刻意偏离**：上一轮决策 2 已定
   「必须是可见按钮，不许做成 accessibility custom action」，理由是低视力通道。
3. **PR 策略**：#141 已合，本轮从 `main` 新开分支。后续每个阶段一个 commit，
   阶段 1–2 合成一个 PR 还是分开，做完阶段 1 再定。
4. **（2026-09-16，答的是原 §2-H）盲人端不做「开始跑步」按钮。**
   ① 汇合的主按钮保留现有的「打电话给张伟」；三秒倒计时改由**订单状态被推到
   `IN_PROGRESS`** 触发（`BlindOrderStatusViewModel.shouldStartRunCountdown`）。
   冷启动时已是 `IN_PROGRESS` 则跳过倒计时 —— 中途进页面的人不该听一遍「准备开始」。
   > 依据：后端 `OrderLifecycleService.java:156` 走 `loadForVolunteer(...)`，
   > `:1025-1026` 对非接单志愿者直接抛 `NOT_ORDER_PARTICIPANT`（403）。
   > 所以原 §2-H 记的「不明」已查清 —— 是**确定调不通**，而那让默认解法
   > 「先做按钮 + 403 兜底」变成「每次按都失败」。已投 handoff 请后端放开；
   > 放开后只需在 ① 加一枚按钮调 `orders.startService`，倒计时那条链路一行不用改。

## 二、待拍板项 —— **2026-09-16 已全部拍板，照下表落，不要再停下来问**

> 七条里 H 当日查清后单独答（见 §1-4），其余六条项目负责人当日一次性批准
> **全部按默认解法落**。表格保留原样是为了留住「为什么是这个默认解法」——
> 只留结论不留理由，下一轮就会有人把它当成可以随手改的选择。

| 编号 | 问题 | 落法（**已批准，直接做**） |
|---|---|---|
| C | 求助中心五项砍掉了 120 / 110 / 主紧急联系人三格（`AGENTS.md` §6 红线），且新增了仓库与契约里都不存在的「人工客服」 | ✅ 保留拨号三格且顺序不动，把设计的五项当「排序要求」而非「清单要求」，改单列；「人工客服」不做，投 handoff |
| D | 设计禁止五星，后端 `CreateReviewRequest.rating` 是 `minimum:1 maximum:5` **必填**且无枚举取值 | ✅ ⑤ 这一屏**推迟**，先投 handoff 请后端加枚举 |
| E | 深色档 7 个 token 与仓库现值不一致（页面底 `#000000` vs `#121417`、正文 `#FFFFFF` vs `#F2F3F5`、品牌蓝 `#0A84FF` vs `#7EA2FF`、求助字 `#FF453A` vs `#FFB4AB` …） | ✅ **不改 `FlowPalette`**（会改每一个已验收界面的深色外观，且对比度用例钉着现值）。E 组按仓库现有深色档做，交付说明里写清偏离 |
| F | 走散/离线的数值后端不下发；阈值也对不上 | ✅ 警示条不写具体数值（用契约的 `ttsText`）；「我们在一起」做成**纯本地**消警；投 handoff |
| G | 电量后端 0 命中 | ✅ 跑者端用本机 `UIDevice.batteryLevel` 自播；陪跑员端那一行不做，投 handoff |
| ~~H~~ | ~~`/start-service` 盲人 token 能不能调不明~~ | **2026-09-16 已答，见 §1-4。** 查清是确定调不通（后端 `loadForVolunteer`），已投 handoff |
| I | 「本次志愿服务时长」只有累计值 `totalServiceMinutes` | ✅ 投 handoff 要单次值 |

## 三、摸底结论（已核实，**别重查**）

| 事实 | 出处 |
|---|---|
| 盲人端订单页**已经是原地变形**，不是跳页 | `BlindOrderStatusView.swift:1281` 的 `content` 三选一；`:1485` 的 `body` 就是它 |
| 四步骨架已落地 | `BlindOrderFlowView.swift:15` + `FlowStepper`（`FlowComponents.swift:99`）+ `BlindOrderFlowPresentation`（`BlindOrderFlowStep.swift:85`） |
| ~~`IN_PROGRESS` 不进骨架~~ | **2026-09-16 阶段 1 已改**：`blindOrderFlowStep` 对 `.inProgress` 返回 `.metUp`，与汇合同一格。`BlindActiveRunView` 现在是那张卡的**内容区**，不再是一整屏 |
| 设计稿**浅色档与仓库逐值吻合** | `FlowPalette.swift:139-167`：`cta #F6C343` / `onCTA #111A2E` / `help` 三色 / `avatar` / `successBadge` / `nodeStroke` / `progressTrack` / `booking` 三色全中 |
| 字号唯一落点是 `FlowFonts` + `flowFont(size:weight:relativeTo:monospacedDigit:)` | `FlowMetrics.swift:162-217`。**新字号加进 `FlowFonts`，不在视图里写字面量** |
| 跑表体例格式化已有 | `TrackStats.distanceKilometersText / durationClockText / paceClockText`（`OrderTrackModels.swift:53-75`） |
| 每公里里程碑已有且已接线 | `KilometerMilestoneTracker`（`OrderTrackModels.swift:83`）→ `BlindOrderStatusView.swift:991` |
| 提示音有现成合成器 | `ToneSynthesizer.wav(frequencies:segmentDuration:)`，已用于录音起止（`SpeechInputService.swift:152`）与紧急倒计时（`EmergencyAlarm.swift:111`） |
| 🔴 **没有播报队列** | `SpeechService.swift:63-72` 是 `stopSpeaking(.immediate)` —— 后来者打断前者，无优先级、无排队、无丢弃 |
| 🔴 **没有 ActivityKit / Widget target** | pbxproj 只有 3 个 target；`import ActivityKit` / `NSSupportsLiveActivities` / `.appex` 全 0 命中 |
| 震动只有三档语义 | `HapticFeedback.play(.success/.warning/.error)`；渐强震动只有 `EmergencyAlarm` 里的 `CHHapticEngine`（`EmergencyAlarm.swift:154`） |
| 求助中心是 `LazyVGrid` 两列（AX 档降一列） | `SafetyHubView.swift:250-294`；格子清单在 `BlindActiveRunSafetyHubOption.tiles`（`SafetyModule.swift:622`），最多 7 格 |
| 后端确实有 `GET /api/orders/{id}/track` 且 `blindStats` 单位是**米 / 秒 / 秒每公里** | `api_spec.yaml:3014` 与 `TrackStatsDto`（`:6966`）。路径参数名是 `id` 不是 `orderId` |

### 设计包自身的三个缺口（已确认，不是没找到）

1. README 的映射表指向「下方**与现有实现的差异**」一节 —— **README 里没有这一节**。
   跑步中那屏保留现有实现的哪些部分是空白的，这正是决策 1 回答的问题。
2. **里程字号自相矛盾**：README 写「82（基准 70）」；清单 §22 写「70×1.76＝123」；
   §23 写「123→101（`minimumScaleFactor(0.7)`）」。123×0.7＝86 ≠ 101，
   而 **82×1.76＝144，144×0.7＝101** ⇒ **基准取 82**，§22 那句是旧值。
3. `#FBE6AE`（倒计时禁用态浅黄）不在仓库调色板、也不在 README 的 token 表里。
   ⇒ 新增具名 token `ctaDisabled`（浅深同值），**不要用 `.opacity`** —— 那会把文字一起淡掉，
   对比度不可控，而这是「准备中」那三秒唯一的视觉状态。

---

## 四、阶段计划（一个阶段一个 session，别在一个 session 里连做两个）

- [x] **阶段 1 · A 组 ①②③ 原地变形 + 主按钮位置不动**（2026-09-16 完成，真机已验）

      ```
      BlindRunPhaseTests + BlindOrderFlowPresentationTests
        + FlowDesignSystemTests + BlindActiveRunTests   passed=58 failed=0
      EmergencySOSTests + KeepWaitingTests               passed=77 failed=0
      testBlindOrderStatusKeepsEmergencyReachableWithoutScrolling  passed=1 failed=0
      testSafetyHubPutsEmergencyFirstInTheAccessibilityOrder       passed=1 failed=0
      ```
      设备 iPhone 16 Pro，`transportType: wired`。既有红灯 3+2 条不在本次范围内，未触及。
      ⚠️ 那两条 UI 用例**第三次才过**：前两次都是 `Timed out while enabling automation mode`，
      中间一个字没改。记忆 `ui-test-runner-needs-usb-not-wifi` 原先写「复跑即过」已订正为
      「同一签名最多复跑三次再开始查别的」。
- [x] **阶段 2 · 播报队列 + 四种提示音**（2026-09-16 完成，PR #147，真机已验）

      ```
      全量  passed=1288  failed=10  skipped=1  (total=1299)
      新增  AnnouncementQueueTests  22/22 全绿
      ```
      落点：`blindRun/Voice/AnnouncementQueue.swift`（新）+ `SpeechService` 接队列 +
      `configurePlaybackCategory` 加 `.duckOthers`。三个签名都是**带默认值的新参数**，
      230 个既有调用点零改动；显式传优先级的只有求助 / 倒计时 / 按需播报 / 每公里那几处。
      🔴 **同档刻意保留「打断」而不是排队** —— 求助倒计时靠它盖掉上一秒，改成排队会念成
      「3」「3」「2」。用例 `testSamePriorityStillInterruptsSoTheCountdownStaysCurrent` 钉住。
      阶段 1 留的两笔账（倒计时绕开 funnel / 「开始跑步」stopSpeaking 掉别人）都结了。
      ⚠️ **两件只能人耳验、还没验**：① 放着音乐时播报该压低不该暂停；
      ② 静音拨杆打到静音时播报仍要出声。改的是音频会话分类，读代码判不了。

      **既有红灯清单要补 6 条**（`state.md` 此前只记了 audit 那 3+2）：
      `testAuthLifecycleBlindAccountDeletionIsTwoStageAndCompletesOnce` ·
      `testAuthLifecycleEveryLogoutSurfaceRequiresConfirmation` ·
      `testAuthLifecycleVolunteerDeletionRouteAndActiveOrderBlock` ·
      `testMockBlindOrderHidesEmergencyActionInAcceptedStates` ·
      `testMockBlindRunnerBookingSmoke` · `testMockVolunteerOrderFlowSmoke`。
      **已在同一台设备上把 worktree 回退到 `fdc6579`(main) 跑同一组对照**：
      `passed=0 failed=6`，失败集合与断言文案逐条相同 ⇒ 是存量不是回归。建议单开任务查。
- [ ] 阶段 3 · ④ 已完成 + 陪跑员端长按 2 秒结束
- [ ] 阶段 4 · B 组异常警示条 + 求助中心单列重排（先答 C）
- [ ] 阶段 5 · D 组锁屏实时活动（**要新建 Widget Extension target，得动 pbxproj**）
- [ ] 阶段 6 · E 深色 + F AX5 布局

### 并行性（2026-09-16 实查文件重叠面得出，别按阶段编号猜）

**能并行的三条线**（文件基本不交叉，且都不卡待拍板项）：

| 线 | 内容 | 主要动的文件 |
|---|---|---|
| A | 阶段 2 · 播报队列 + 四种提示音 | `Voice/SpeechService.swift`、`Voice/SpeechInputService.swift`（`ToneSynthesizer`）、`BlindOrderStatusView` 约 15 处加优先级 |
| B | 阶段 5 · 锁屏实时活动 | 新 Widget Extension target + `pbxproj` + 新文件；`BlindOrderStatusView` 只加起停钩子 |
| C | 阶段 3 的**志愿者那一半**（长按 2 秒结束） | `Volunteer/VolunteerOrderFlowViews.swift` |

🔴 **线 A 必须给 `speak` 加带默认值的优先级参数，不改既有调用点。**
全仓 `speak`/`speakError`/`announce` 共 **230 个调用点、分布在 31 个文件**，
改签名会把整个仓库碰一遍 —— 那三条线当场全撞。

**必须串行的三件**：阶段 3 的盲人端（④ 已完成）· 阶段 4 · 阶段 6。
三者**都改 `BlindOrderFlowView.swift`**，同一个文件三个人改必撞。

### 阶段 1 要动的文件

**实际落地如下（与开工前的预估表有两处出入，已订正）：**

| 文件 | 改了什么 |
|---|---|
| `BlindOrderFlowStep.swift` | `.inProgress` → `.metUp`（进骨架）；新增 `BlindRunPhase` / `BlindRunCountdown` / `BlindRunTransition` / `BlindRunCopy`；`Visual` 加 `.countdown(Int)` / `.runMetrics`；`PrimaryAction` 加 `.preparing` / `.announceStats`（**没有 `.startRun`**，见 §1-4）；`make` 加 `countdown:` 入参、相位在内部派生 |
| `BlindOrderFlowView.swift` | 进度条 ↔「陪跑中 · 张伟」顶行互换、头像 `matchedGeometryEffect` ⌀92 ↔ ⌀28、信息卡在跑步中不渲染；`transitionAnimation` 按 `reduceMotion` 分档；倒计时圆 + 每拍回弹 |
| `BlindActiveRunView.swift` | **整文件重写**：从一屏深底执行屏变成白卡内容区（里程 82 居中 + 时长/配速两格）。`BlindActiveRunSafetyAnchor` 删除，其中的求助结果面抽成 `BlindRunSafetyResultSection` |
| `BlindOrderStatusView.swift` | `content` 三分支合并成两分支；`runCountdown` 状态机 + `shouldStartRunCountdown` 纯函数；`flowFooter` 接回求助结果面；`isActiveRun` / `repeatStatusArea` 删除；导航栏「重复当前状态」在 ③ 收起 |
| `FlowMetrics.swift` | `FlowFonts` 加 `runDistance()` 82 / `runMetric()` 36 / `runPrimaryLabel()` 16 / `runSecondaryLabel()` 15 / `partnerHeadline()` 15 / `countdownNumber()` 52；`avatarInitial(diameter:)` 加 13 这一档；`FlowMetrics` 加 ⌀28 小头像与顶行内边距 |
| `FlowPalette.swift` | 加 `ctaDisabled` / `ctaDisabledTone`（`#FBE6AE`，浅深同值） |
| `FlowComponents.swift` | `FlowActionButton` 加 `isEnabled`（→ `.disabled()` + `ctaDisabled` 底） |
| `blindRunTests/BlindRunPhaseTests.swift`（新） | 相位派生、倒计时四条边界（含穷举）、主按钮版位不空、顶行去掩码 |

**阶段 1 的 code review 结论（2026-09-16，A 档 7 条）：**

修了 6 条 —— 倒计时触觉换 `.tick`（原来 `.success` 与状态变化那次撞车，3 秒 4 下同波形）·
倒计时补「离开 `IN_PROGRESS` 就取消」（原来只 return，志愿者 3 秒内取消会继续念「2」「1」）·
倒计时走完补「开始跑步」+ 强震（原来变形完成那一刻零信号）· 定位行文案进 `BlindRunCopy` ·
跑步中藏返回箭头（核过：`.toolbar(.hidden, for: .tabBar)` 全仓 0 命中 ⇒ 切 tab 仍可离开，
**将来谁隐藏标签栏，这一行必须同时撤销**）· reduceMotion 改**瞬时切换**。

**没修 1 条（项目负责人当轮决定）**：求助结果面（`BlindRunSafetyResultSection`）从常驻底栏
挪进了滚动区。默认字号下仍在第一屏，字号往上调一两档会被推出去，而**没有任何检查会说话**
—— 就是记忆 `claimed-fallback-may-not-exist-in-release` 那个形状。
最急那条路径落在 `EmergencyCountdownView` 全屏里，这一块是关掉全屏后回到跑步页的残留面。
要治两条路：挂回 `bottomActions` 上方固定位，或在 UI 测试里补一条
「失败态下 `blindActiveRunFailureCallButton.frame.maxY <= app.frame.maxY`」并在 AX 档跑一次。

⚠️ **review 的 A-7 有一条数字是错的，别照抄**：它说 `AppColors.success/.warning` 压白卡
只有 2.20:1，实测是 **5.07 / 5.20**（`#1B7F3B` / `#B25000`，它拿的是猜的 `#FF9500`）。
照它另造的一对 `Flow` 色反而把暗色档从 8.42 拉到 3.89，已撤回。

**遗留在原地没动的东西**（下一轮别当成缺陷去查）：
`AppColors.activeRunSurface` / `activeRunSecondaryText` / `activeRunDestructive` 三个取值
现在**盲人端没有渲染点了**，但 `LowVisionChannelTests` 还在验它们的对比度。
刻意不删：陪跑员端跑步中那屏（C 组，阶段 3）大概率还要用同一套深底。
到阶段 3 若确认不用，连同那 3 条用例一起删。

---

## 五、验证纪律（**一个字都不要跳过**）

- **CI 跑不了任何 XCTest**（高德无 arm64-sim slice）。CI 绿只等于编译门禁 + 规格校验过了。
- 真机是唯一 XCTest 通道：`scripts/device-test.sh`，命令行必须带 `DEVELOPMENT_TEAM=ZW39BS8NXT`。
- **默认只跑覆盖本次改动的 suite**，不要裸跑全量（约 10 分钟，会超 Bash 600s 上限）。
  全量只留给「全 App 唯一出口 / 共享单例 / 全局配置」类改动。
- **`passed=0` 一律当失败查。** 零执行不是通过。
- 设备：iPhone 16 Pro `00008140-000161D62112801C`（脚本默认）。
  iPad Air 5 `00008103-001C71490E62201E` **还没点过「信任证书」**，跑不了。
- **要插 USB**。判有线只看 `devicectl list devices --json-output` 的
  `connectionProperties.transportType`；`ioreg -p IOUSB | grep -i iPhone` 会给假阳性。

### 已知既有红灯（**不是你改出来的**，判回归时要扣掉）

- `AccessibilityAuditTests` 3 条长期红。
- `testBlindOrderStatusInLandscapePassesAccessibilityAudit` 2 条 `Contrast failed` ——
  逐个量过调色板声明值全部过线，**唯一不过线的是 1.5pt 描边的抗锯齿边缘像素**
  （实测混合色 `#CD6F5F` 压 `#FDEFEF` ＝ 3.11:1）。**已分出独立任务**，本轮不碰调色板。
  ⛔ 别直接加 `auditIgnoredIdentifiers` 豁免了事 —— 那等于用绿灯替一个没查清的问题背书。
