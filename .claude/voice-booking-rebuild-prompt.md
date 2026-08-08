# 任务：把「创建预约」页从「表单 + 语音输入」改成真正的语音优先页

> 这是一份自足的开工 prompt。新 session 直接执行，不依赖任何上文。
> 你**不得**把本文件里的事实当成已核实的 —— 凡是文件路径、行号、函数名，落笔前自己读一遍。
> 本文件写于 2026-08-08，代码在变。

---

## 1. 用户的原话与问题

> 「我想要修改的是点击开始约跑后进入语音预约的那个地方。语音的那个表单现在它是太过于的复杂了，
> 它是表单的形式，但表单的形式不应该给盲人用。」

**目标页**：`blindRun/BlindRunner/BlindBookingView.swift`（导航栏标题「创建预约」，1523 行）。
从盲人首页按「开始约跑」进入，入口是 `BlindRunnerHomeView` 的 `BlindRunnerRoute.voiceBooking`，
构造参数 `startsWithVoice: true`。

**问题的具体形态**（读 `BlindBookingView.swift:762-782` 的 `body`）：

```swift
ScrollView {
    VStack(alignment: .leading, spacing: 24) {
        header
        voiceOrderSection      // 语音向导
        guidedStepHeader       // ↓ 四步表单，无条件渲染
        currentStepContent     // ↓ 和语音区并排堆在同一个滚动视图里
        ...
    }
}
```

四步是 `BlindBookingGuidedStep`：`startPoint` / `appointmentTime` / `runningNeeds` / `review`
（定义在同文件 `:36` 附近）。`currentStepContent`（`:1033`）分发到 `locationSection`（`:1046`）、
`appointmentSection`（`:1255`）、`optionalSection`（`:1280`）、`reviewSection`（`:1357`）。

**实测的读屏可见内容**（2026-08-08 真机 XCUITest 抓的 a11y 树，Mock 环境、盲人角色、
`startsWithVoice: true`）—— 一屏之内同时存在：

```
StaticText  创建预约
StaticText  按步骤确认出发地点、预约时间和选填需求，最后再提交
StaticText  请说你想从哪儿出发、什么时候跑、跑多久，比如：明天早上八点从人民广场出发跑一个小时。说完再点一下就好。
StaticText  确认出发地点
StaticText  当前步骤：确认出发地点。正在使用演示坐标，不代表真实会合点。出发地点：北京市（演示位置）。确认地点后进入预约时间。
StaticText  出发地点
StaticText  默认出发点
StaticText  出发地点，北京市（演示位置）
StaticText  使用演示坐标，适合模拟器测试
StaticText  搜索出发地点
TextField   搜索出发地点（占位：例如：科技园地铁站 A 口）
Button      语音输入搜索出发地点
Button      搜索地点（Disabled）
StaticText  出发地点补充描述
TextField   出发地点补充描述（占位：例如：我在 A 口外侧等候）
Button      语音输入出发地点补充描述
StaticText  定位暂不可用，正在使用演示坐标。
StaticText  辅助地图
...（还有下文，四步全在同一个滚动视图里）
```

**诊断**：这不是「语音下单页」，是「一张表单，外加给每个字段配了一个麦克风按钮」。
盲人用户进来面对的是十几个 StaticText 加两个文本框，语音区只是其中一块。
「表单不该给盲人用」说的就是这件事。

---

## 2. 要做什么（方向，不是最终方案 —— 先出计划让用户批）

**核心判断**：语音优先意味着**表单不在这一页上**，而不是「表单上面加一块语音区」。
表单要退成显式的逃生口 —— 底栏那个「改用表单」按钮（见 `BlindBookingView.swift:794` 的注释，
它在 `safeAreaInset` 里，`formControls` 在 `:1443`）。

可能的形态（**由你调研后提方案，不要直接照抄**）：
- 进页面即录音，屏幕上只有「正在听」这一个状态 + 一个巨大的可点区域
- 说完 → 读回整单 → 一个确认动作
- 需要改哪一项 → 定点修改，而不是退回四步表单
- 解析失败 / 麦克风被拒 / 说不清楚 → 才落到表单，且是**整页切换**，不是并排共存

**这一页现在已经有的东西不要重造**（先读再改）：
- `blindRun/Voice/VoiceOrderWizard.swift`（794 行）—— 一句话下单向导已经实现了，
  含读回整单、确认词白名单、定点修改、尾静音。**你的活多半是改「表单还在不在这一页」，
  不是重写向导。**
- 整屏可点区（`:795-809`）+ Magic Tap（`:816`）：录音时=「我说完了」，播报时=「别念了」。
  这两块有详细的设计理由注释，动之前读完。

---

## 3. 现成的调研资料（先读，别重新查一遍）

| 文件 | 内容 | 怎么用 |
|---|---|---|
| `docs/research/blind-voice-booking-ia-20260805.md`（1276 行） | 语音预约的**交互契约**调研：焦点数上限、确认词白名单、尾静音阈值、竞品逐个拆解、标准编号 | 这是本任务的主要依据。**§9「反对意见与已知失败模式」必须读** —— 里面有「一句话下单」的已知失败案例和「极简对视障用户的负面影响」，不要只看支持的一面 |
| `docs/research/blind-ui-visual-benchmark-20260808.md` | **视觉**规则：一个动作占满内容区、次级操作全宽竖排不并排、一行只放「一个名字 + 一个数字」、地图是装饰 | 定「改完长什么样」 |
| `docs/05-page-specs.md` | 创建预约页规格，含「语音下单：一次说完 → 读回整单 → 确认或定点修改」小节 | 改行为前先对规格 |
| `docs/09-accessibility-and-voice-guidelines.md` | 必播报节点、读回整单三段式、**时长取整必须说出来**、语音不可用时的降级播报 | 播报文案的硬约束 |
| `openspec/changes/enable-one-utterance-booking/` | **未归档**的 OpenSpec 变更，proposal / design / tasks / specs 四份齐 | 本任务大概率是它的 delta。未完成项：`2A.8`（后端歧义未解）、`3.7`（UI 测试未写未跑）、`5.5`（真机开 VoiceOver 手测未做） |

对标产品截图（App Store 官方，31MB，**已 gitignore**，要看自己抓）：

```bash
node scripts/fetch-reference-screenshots.mjs
```

抓完在 `docs/ui/reference-screenshots/`。关键帧：`be-my-eyes/03`（一个按钮占内容区 75%）、
`aira-explorer/02`（次级操作全宽竖排）、`xiaoai-bangbang/02`（进行中页面只有一个动作）。

---

## 4. 硬约束（违反会被 CI / hook 拦，或造成线上缺陷）

先完整读 `AGENTS.md`，下面只是与本任务直接相关的摘录：

- **下单起始时间距今不足 30 分钟必须报 `APPOINTMENT_TOO_SOON`**（`EnvironmentConfig.minimumBookingLeadMinutes = 30`）。
  **没有「现在就跑」。** 语音里说「现在」必须被挡下并播报原因。
- **确认词白名单只保留 ≥3 音节的显式短语。**「好」「行」「对」「是」这类单音节词绝不能当确认 ——
  2018 年 Portland 事件里背景对话中的 "right" 满足了确认并完成了不可撤销动作，
  而陪跑场景志愿者就在旁边说话。依据见 IA 调研 §6.4。
- **枚举解码遇未知值不许整条崩**，要降级到「未知」。对盲人端「点了没反应」就是事故。
- **契约唯一源在后端仓库** `/Users/mac/Downloads/demo/docs/api_spec.yaml`。本仓库的
  `docs/_archive-*.bak` **不得读取**。要后端改动就写进 `demo/docs/handoff.md` 的「待后端确认」。
- **并发模型只用一种**：新代码一律 async/await，不要在同一条数据流里既订阅 Combine 又 await。
- **不得写入 `EXCLUDED_ARCHS`**；不得改 `project.pbxproj` 里的 `DEVELOPMENT_TEAM`；`Podfile` 整文件冻结。
- 守卫在 `scripts/hooks/guard.mjs`，自测 `node scripts/validate-guard.mjs`（28 条）。
  规则清单以该文件为准。

---

## 5. 验证纪律（这条最容易被糊弄过去）

**模拟器永久不可用**（高德 SDK 无 arm64-sim slice），XCTest 只能真机跑。

```bash
# 无真机时的编译上限
xcodebuild -workspace blindRun.xcworkspace -scheme blindRun \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build-for-testing

# 真机（唯一 XCTest 通道）——先按符号搜出范围，只跑命中的 suite，不要裸跑全量
scripts/device-test.sh -only-testing:blindRunTests/VoiceOrderWizardTests

node scripts/validate-guard.mjs
node scripts/validate-docs.mjs
openspec validate --all --strict --no-interactive
```

- **命令行传测试要带 `DEVELOPMENT_TEAM=ZW39BS8NXT`**（工程里写死的是别人的团队号）。
- **零执行不是通过**：`passed=0` 一律当失败查（设备锁屏、`-only-testing` 名字打错、
  测试目标没编出来都长这样）。
- **先定范围再跑**：把你改到的类型 / 方法名拿去 `blindRunTests` 里搜，只跑命中的 suite。
  全量约 10 分钟且会超 Bash 600s 上限。只有改到全 App 唯一出口 / 共享单例
  （`SystemSpeechAudioSession`、`APIClient`、`AppState`）才必须全量。
- **本任务几乎必然要动 `SystemSpeechAudioSession` 或其调用链** —— 如果动了，**必须全量**。
- **音频正确性代码读不出来**：调用点顺序参数全对也可能一声不响（`.record` 分类不开输出通道）。
  改到音频会话要真人耳朵听，并且要想清楚「现在什么会真的响、响的时候麦克风开着吗」。

---

## 6. 已知的坑（别再踩一遍）

- **UI 测试里禁止 `app.tap()`** —— 它敲屏幕正中，而盲人端主按钮的设计目标就是占满那里，
  一敲就导航走；症状会伪装成「页面没起来」。已落成守卫 `blind-tap-center`。
  要触发 interruption monitor 用：
  `app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()`
- **UI 测试断言前先滚动**：SwiftUI `List` 不渲染屏幕外的行，直接断言会假失败。
- **`BlindBookingViewModel` 的 `appState` / `locationService` / `placeSearchProvider` 是 `weak`** ——
  测试里传当场构造的临时对象等于传 nil，断言会「绿」但什么都没测。要先 `let` 住再传。
  守卫 `weak-temporary` 会拦。
- **构造「缺失定位」状态用 `LocationService.simulateMissingDeviceLocationForTesting()`**
  （`blindRun/Map/LocationService.swift:169` 附近），别裸构造 `LocationService()` —— 真机 CoreLocation
  几毫秒就回调，那是竞态。
- **两条无障碍审计用例本来就是红的**（`testBlindRunnerHomePassesAccessibilityAudit` /
  `testBlindBookingPassesAccessibilityAudit`），报警集中在 DEBUG-only 的开发者面板与
  `.secondaryLabel` 文字对比度上。详见 `docs/research/blind-ui-visual-benchmark-20260808.md` §5。
  **别把它们的红当成你改坏的**，也别顺手去修（那是另一件事）。
- **本机 python3 联网必崩** `SSL CERTIFICATE_VERIFY_FAILED`，抓网络内容用 `curl` 或 node `fetch`。

---

## 7. 已经做完的事（不要重做）

分支 `feat/blind-home-primary-action-scale`（已推送，3 个 commit）改的是**另外两页**：

- **盲人首页** `BlindRunnerHomeView.swift`：主按钮 64pt → 280pt、删说明文字、
  标题与状态摘要合并成一个 VoiceOver 焦点、错误态「重试加载」补到 64pt。
- **订单状态页** `BlindOrderStatusView.swift`：7 个 section 收到 4 个，
  「打电话给志愿者」提为主按钮，删掉两块与 `statusHeader` 逐字重复的卡片。

**创建预约页一行没动。** 那就是你的活。

按「一个 PR 只装一件事」，**新开分支**，不要沿用上面那个。

---

## 8. 开工顺序

1. 读 `AGENTS.md` → 读第 3 节列的调研与规格 → **完整读一遍** `BlindBookingView.swift` 与
   `VoiceOrderWizard.swift`（探索可以派 subagent，编辑前自己读）
2. 进 plan mode，出方案：会改哪些文件、表单退到哪里、失败路径落到哪里、风险是什么。
   **停下来等用户批**，不要直接写码
3. 方案批了之后，同步 `openspec/changes/enable-one-utterance-booking/` 的四份 artifact
   （proposal → design → tasks → specs 一起过，specs 最容易被忘）
4. 实现 → 按符号搜定范围 → 真机跑 → **把真实输出贴出来**
5. 跑 `/code-review`，并明确告诉它「只报影响正确性或违反既定需求的，其余当可选」
6. commit（`type: 描述`，不带 `Co-Authored-By`）→ push。Stop 钩子会强制这两步

---

## 9. 开工前该问用户的问题（不要自己拍板）

1. **表单还留不留在这一页可达？** 只留底栏「改用表单」，还是彻底移到设置里？
   —— 不同答案会做出完全不同的东西。
2. **麦克风权限被拒 / 连续听不清时落到哪里？** 现在是落回表单。如果表单不在这一页了，
   降级路径需要重新定义。
3. **IA 调研 §3.2.1 建议给下单加「配速区间」和「训练距离」两个匹配维度**
   （United In Stride 的匹配维度里有，我们没有；配速不匹配的志愿者接单等于无效派单）。
   —— 本次做不做？做的话要先走后端契约，不在这个 PR 里。
