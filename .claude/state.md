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

## 二、还没拍板（到对应阶段**先问**，别自己选）

| 编号 | 问题 | 我给的默认解法（**要先问过才能落**） |
|---|---|---|
| C | 求助中心五项砍掉了 120 / 110 / 主紧急联系人三格（`AGENTS.md` §6 红线），且新增了仓库与契约里都不存在的「人工客服」 | 保留拨号三格且顺序不动，把设计的五项当「排序要求」而非「清单要求」，改单列；「人工客服」不做，投 handoff |
| D | 设计禁止五星，后端 `CreateReviewRequest.rating` 是 `minimum:1 maximum:5` **必填**且无枚举取值 | ⑤ 这一屏**推迟**，先投 handoff 请后端加枚举 |
| E | 深色档 7 个 token 与仓库现值不一致（页面底 `#000000` vs `#121417`、正文 `#FFFFFF` vs `#F2F3F5`、品牌蓝 `#0A84FF` vs `#7EA2FF`、求助字 `#FF453A` vs `#FFB4AB` …） | **不改 `FlowPalette`**（会改每一个已验收界面的深色外观，且对比度用例钉着现值）。E 组按仓库现有深色档做，交付说明里写清偏离 |
| F | 走散/离线的数值后端不下发；阈值也对不上 | 警示条不写具体数值（用契约的 `ttsText`）；「我们在一起」做成**纯本地**消警；投 handoff |
| G | 电量后端 0 命中 | 跑者端用本机 `UIDevice.batteryLevel` 自播；陪跑员端那一行不做，投 handoff |
| H | `/start-service` 盲人 token 能不能调不明 | 先做按钮 + 403 兜底，同时投 handoff |
| I | 「本次志愿服务时长」只有累计值 `totalServiceMinutes` | 投 handoff 要单次值 |

## 三、摸底结论（已核实，**别重查**）

| 事实 | 出处 |
|---|---|
| 盲人端订单页**已经是原地变形**，不是跳页 | `BlindOrderStatusView.swift:1281` 的 `content` 三选一；`:1485` 的 `body` 就是它 |
| 四步骨架已落地 | `BlindOrderFlowView.swift:15` + `FlowStepper`（`FlowComponents.swift:99`）+ `BlindOrderFlowPresentation`（`BlindOrderFlowStep.swift:85`） |
| `IN_PROGRESS` 目前**不进骨架** | `BlindOrderFlowStep.swift:56` 返回 `nil`，走 `BlindActiveRunView` |
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

- [ ] **阶段 1 · A 组 ①②③ 原地变形 + 主按钮位置不动** ← 下一件
- [ ] 阶段 2 · 播报队列 + 四种提示音
- [ ] 阶段 3 · ④ 已完成 + 陪跑员端长按 2 秒结束
- [ ] 阶段 4 · B 组异常警示条 + 求助中心单列重排（先答 C）
- [ ] 阶段 5 · D 组锁屏实时活动（**要新建 Widget Extension target，得动 pbxproj**）
- [ ] 阶段 6 · E 深色 + F AX5 布局

### 阶段 1 要动的文件

| 文件 | 改什么 |
|---|---|
| `blindRun/BlindRunner/BlindOrderFlowStep.swift` | `PrimaryAction` 加 `.startRun` / `.countdown` / `.announceStats`；决定 `IN_PROGRESS` 怎么进骨架 |
| `blindRun/BlindRunner/BlindOrderFlowView.swift` | 进度条上折、「陪跑中 · 张伟」展开、头像**同一个视图**从 ⌀92 缩到 ⌀28、信息卡下沉淡出；`reduceMotion` 走 300ms 纯淡入淡出但**保留倒计时** |
| `blindRun/BlindRunner/BlindActiveRunView.swift` | 内容区重写成白卡三数字（里程 82 居中 / 时长 / 配速），按决策 1 保留三件 |
| `blindRun/BlindRunner/BlindOrderStatusView.swift` | 分支合并、倒计时状态机、真实调 `startService` |
| `blindRun/Core/DesignSystem/FlowMetrics.swift` | `FlowFonts` 加：里程 82 / 次级 36 / 顶行 15；`FlowMetrics` 加小头像 ⌀28 |
| `blindRun/Core/DesignSystem/FlowPalette.swift` | 加 `ctaDisabled`（`#FBE6AE`，浅深同值） |
| `blindRunTests/BlindRunPhaseTests.swift`（新） | 相位机 + presentation 穷举 |

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
