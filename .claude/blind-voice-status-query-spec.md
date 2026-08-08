# 盲人端语音查订单状态

> 本文件是**自足**的开工文档。新 session 只有这个文件、没有产生它的对话，也应该能做对。
> 位置沿用 `.claude/voice-booking-rebuild-prompt.md`（commit `7d0454c`）的既定做法。
> 产出日期 2026-08-08。**实现中发现本文档错了，先改本文档再继续**，不许闷头按错的 spec 做完。

---

## 目标

盲人用户在首页和订单状态页按下一个「问一句」按钮，说一句自然话（「志愿者还有多远」「几点开始」
「给他打个电话」），App 用本地关键词判断意图，只播报被问的那一项；听不出意图就念现有的整段状态
播报，并在末尾告诉用户能问哪些。

解决的问题：现在盲人要知道「志愿者还有多远」，只能用 VoiceOver 逐个滑到那一行，或者按
「重复当前状态」听完 15~25 秒的整段。语音入口把「找 + 听全部」压成「问 + 听一句」。

---

## 范围

### 做

1. 首页（`BlindRunnerHomeView`）与订单状态页（`BlindOrderStatusView`）各加**一个** 64pt 的
   「问一句」按钮，按下才开始录音。
2. 四个意图，全部走**本地关键词匹配**，不发任何网络请求：
   | 意图 | 触发词（示例，非穷举） | 回答 |
   |---|---|---|
   | `distance` | 多远、到哪了、什么时候到、快到了吗、还有多久 | 志愿者到出发地点的**直线距离** |
   | `status` | 什么状态、到哪一步、接单了吗、怎么样了 | 订单状态名 + 该状态的盲人端说明 |
   | `schedule` | 几点、时间、在哪、出发地点、集合 | 预约时间 + 出发地址 |
   | `callVolunteer` | 打电话、联系志愿者、给他打个电话、拨号 | 复述号码 → 语音确认 → 拉起系统拨号 |
3. **兜底**：关键词都没命中 → 念现有整段状态播报
   （`order.blindRunnerAnnouncement(distanceText:)`），**再追加一句**可问清单：
   「你还可以问：志愿者还有多远、几点开始、打电话给志愿者。」
4. **空数据口径**：问了但当下没这个数据（例：`PENDING_MATCH` 时问距离），必须**说清为什么没有 +
   当前状态**，不许只说「暂时没有这个信息」。
5. 打电话必须**语音复述号码 + 等一次语音确认**才拨号。

### 不做（明确排除，防止执行时自己扩范围）

- ❌ **取消订单，以及任何其他不可逆动作**。识别到「取消」一律回
  「取消需要在屏幕上确认，请找取消订单按钮」，**不得**代为取消。
- ❌ **ETA / 到达时间估算 / 路线规划**。只念直线距离，不调高德路线 API，不按步速换算分钟数。
- ❌ **历史订单、多单查询、订单消歧**。只回答「当前这一单」；不碰 `/api/orders/mine`。
- ❌ **后端 NLU**。不调 `/api/orders/voice/parse`，不改后端契约，不写新的 handoff 需求条目。
- ❌ **志愿者端**。本期只有盲人端两页。
- ❌ **预约页 `BlindBookingView`**。那一页正在跑 `VoiceOrderWizard`，加第二个录音入口会与
  向导抢 `SpeechInputService` 的单会话。
- ❌ **唤醒词 / 摇一摇 / Siri App Intents**。入口就是屏幕上一个按钮。
- ❌ **不动黄金语料**。`demo/docs/voice-golden-corpus.json` 和
  `blindRunTests/VoiceOrderWizardTests.swift` 里的镜像清单是**下单**语料
  （DURATION / START_TIME / ADDRESS / GUIDE_DOG / PACE），与本期无关。碰它会让
  `scripts/validate-golden-corpus.mjs` 报错。
- ❌ **不重写 `SpeechService` / `SpeechInputService` 的既有行为**。只新增枚举 case 和调用点。

---

## 涉及的文件与接口

### 新建：`blindRun/Voice/VoiceStatusQuery.swift`

**纯函数、无 UIKit / SwiftUI / 网络依赖**，这样单测不需要真机硬件。

```swift
enum VoiceStatusIntent: Equatable {
    case distance
    case status
    case schedule
    case callVolunteer
    /// 识别到破坏性词汇（取消/退单），必须显式拒绝而不是落进 unrecognized 的整段兜底。
    case blockedDestructive
    case unrecognized
}

struct VoiceStatusAnswer: Equatable {
    let speech: String
    /// 非 nil 时表示这次回答后还要做一件事（本期只有拨号，且必须先确认）。
    let pendingAction: PendingAction?

    enum PendingAction: Equatable {
        case confirmDialVolunteer(phone: String)
    }
}

enum VoiceStatusQuery {
    static func classify(_ transcript: String) -> VoiceStatusIntent

    /// - Parameter volunteerCoordinate: 已判过新鲜度的志愿者坐标；过期或没有一律传 nil。
    /// - Parameter fallbackAnnouncement: 兜底整段，调用方传
    ///   `order.blindRunnerAnnouncement(distanceText:)` 的结果。
    static func answer(
        intent: VoiceStatusIntent,
        order: OrderDetailResponse?,
        volunteerCoordinate: CLLocationCoordinate2D?,
        fallbackAnnouncement: String
    ) -> VoiceStatusAnswer

    /// 兜底时追加的那句。单独暴露，测试里对得上字面量。
    static let askableHint = "你还可以问：志愿者还有多远、几点开始、打电话给志愿者。"

    /// 判定用户是否用语音确认了拨号。复用 `VoiceOrderWizard.isAffirmative` 的同一套判定，
    /// 不要另写一套「是/对/好」的表。
    static func isDialConfirmed(_ transcript: String) -> Bool
}
```

### 改动

| 文件 | 改什么 |
|---|---|
| `blindRun/Voice/SpeechInputService.swift:271` | `SpeechInputField` 加两个 case：`voiceStatusQuery`、`voiceStatusConfirmCall`。`isAllowlisted`（`:290`）用 `rawValue` 反查，加了 case 自动生效，**不用改它**。 |
| `blindRun/BlindRunner/BlindRunnerHomeView.swift` | `BlindRunnerHomeViewModel` 加 `askVoiceQuestion()`；`homeSections`（`:531`）在 `repeatStatusButton`（`:752`）**之前**插入「问一句」按钮。 |
| `blindRun/BlindRunner/BlindOrderStatusView.swift` | `BlindOrderStatusViewModel` 同样一个方法。距离直接用已有的坐标 `latestVolunteerCoordinate`（已过新鲜度闸），**不要**再判一遍。 |
| `blindRunTests/VoiceStatusQueryTests.swift`（新建） | 见「验收」。 |

**实现时改掉的两条（2026-08-08，按本文件开头的规矩先改文档）：**

- 原写「两个 view model 各加 `askVoiceQuestion()` 与 `handleVoiceTranscript(_:)`」。实际只在
  两个 view model 各加 `askVoiceQuestion()`，转发给新建的 `blindRun/Voice/VoiceStatusQuerySession.swift`
  （录音 → 答 → 拨号确认 → 拨号）。**理由**：两页的差别只有「订单和坐标从哪来」，
  而拨号确认那一段是安全逻辑；抄两份等于这条保证要守两遍（`AGENTS.md` §1）。
  `VoiceStatusQuery` 仍是纯函数、仍是单测的唯一对象。
- 新增 `RunOrderStatus.offersVolunteerDistanceToStart`（`OrderDisplayHelpers.swift`）。
  `[.pendingAccept, .driverEnRoute, .driverArrived]` 这个三元组原本在 `BlindOrderStatusView`
  里抄了两遍（`:442` / `:450`），语音入口是第三遍。写成穷举 switch，后端加状态时编译器逼一次决策。

### 现成可用的接口（照抄签名，别自己造）

```swift
// 录音。单会话：同一时刻只有一个 field 在录，重复调会先停掉上一个。
// blindRun/Voice/SpeechInputService.swift:424
func startRecognition(
    field: SpeechInputField,
    onTextChanged: @escaping (String) -> Void,
    onAnnouncement: ((String) -> Void)? = nil,
    onCompletion: ((SpeechInputCompletion) -> Void)? = nil
)

// 播报。blindRun/Voice/SpeechService.swift:34（`SpeechService` 是 `VoiceService` 的 typealias，:188）
func speak(text: String)
func speakError(_ message: String)

// 整段兜底文案。blindRun/Core/Models/OrderDisplayHelpers.swift:209
func blindRunnerAnnouncement(distanceText: String? = nil) -> String

// 直线距离文案（返回如「距出发地点约 800 米」，算不出返回 nil）。
// blindRun/Core/Models/OrderDisplayHelpers.swift:203
func volunteerDistanceToStartText(from volunteerCoordinate: CLLocationCoordinate2D?) -> String?

// 预约时间 / 出发地址。OrderDisplayHelpers.swift:199 / :195
var plannedStartForAnnouncement: String?   // 可空
var startAddressForAnnouncement: String    // 不可空，无地址时有兜底文案

// 拨号 URL。用它，别自己拼 tel: 字符串。
EmergencyDialer.telURL(for: phone) -> URL?

// 首页取志愿者最新坐标（同步取缓存）。blindRun/Core/AppRealtimeCoordinator.swift:555
func latestPeerLocation(orderID: Int64, ownerRole: RealtimePeerRole) -> RealtimePeerLocationSample?
```

### 数据事实（不要凭印象，这几条已核实）

- `OrderDetailResponse`（`blindRun/Core/Models/OrderModels.swift:302`）**没有 `volunteerName` 字段**，
  只有 `volunteerPhone: String?`。复述拨号只能说号码，**不许编造志愿者姓名**。
- `volunteerDistanceToStartText` 只在 `PENDING_ACCEPT` / `DRIVER_EN_ROUTE` / `DRIVER_ARRIVED`
  三态有值（`BlindOrderStatusView.swift:440`）。其余状态一律 nil。
- 打电话按钮已存在于订单状态页（`BlindOrderStatusView.swift:828`），条件是
  `order.status.offersVolunteerCall && volunteerPhone != nil`。**语音路径必须复用同一个条件**，
  不许绕过它在不该打电话的状态下拨号。
- `latestPeerLocation` **不做新鲜度过滤**，只是取缓存。状态页在
  `handleVolunteerLocationUpdate`（`:335`）里用 `guard age <= peerFreshness` 判过。
  **首页自己调 `latestPeerLocation` 时必须自己判新鲜度**（`LiveEscortSessionCoordinator.peerFreshness`），
  否则会念一个几分钟前的距离 —— 对听不见屏幕的人，那就是假数据。

---

## 决策

| 决定 | 理由 | 否掉了什么 / 为什么否 |
|---|---|---|
| 意图识别放**本地关键词匹配** | 查状态只有 4 个意图，关键词就够；不发网络、断网可用、不新增契约 | **后端 NLU**：`/api/orders/voice/parse` 在生产上**恒 404**（`VoiceOrderWizard.swift:413` 已实证，前端为此专门写了「语音下单暂时用不了」的降级分支）。按它的契约写完，盲人拿到手的是一个恒报错的按钮。**「先写客户端 + 提 handoff 等后端」**同样否掉：本期端到端跑不通，验收只能靠 mock，而 mock 永远不是发布签核依据（AGENTS.md §3） |
| 「志愿者什么时候到」**只念直线距离** | `volunteerDistanceToStartText` 是现成数据，零新增依赖，且不会给出做不到的时间承诺 | **高德路线规划算真 ETA**：新增外部调用 + key 用量 + 超时/失败分支 + 频率控制，本期不值。**按步速换算分钟数**：直线距离在城市路网里换算出的时间会系统性偏乐观，对盲人是有害的精确 |
| 打电话要**语音复述号码 + 一次语音确认** | ASR 会听错，而盲人用户拨错电话很难自己发现和撑销 | **直接拉起系统拨号盘**：系统那层确认对看得见的人够用，盲人可能已经不知道自己到了拨号界面 |
| **不支持语音取消订单** | ASR 会把「不取消」听成「取消」，而订单取消不可逆 | **两道确认后支持**：多一条不可逆路径要守，收益是省一次点击，不成比例 |
| 听不懂时**念整段 + 追加可问清单** | 用户永远拿得到答案，同时下次知道怎么问 | **只念整段**：用户学不会问法。**只念清单**：这一次他没得到答案 |
| 空数据时**说清原因 + 当前状态** | 盲人要能分清「功能坏了」和「现在就没这个数据」 | **直接降级念整段**：用户会以为自己问错了 |
| 入口是**屏幕上一个按钮** | 与现有交互一致，不耗电，不需要新权限 | **摇一摇**（误触率高，与系统「摇动撤销」语义打架）、**唤醒词**（后台常听，iOS 限制严格且耗电）、**Siri App Intents**（要新建 target + Siri 授权，回答内容受 Siri 播报限制） |
| 范围**只有首页 + 订单状态页** | 两页覆盖盲人端全部订单场景 | **预约页**：正在跑 `VoiceOrderWizard`，两套录音抢同一个 `SpeechInputService` 单会话 |
| 意图判定写成**纯函数**放独立文件 | 单测不需要真机硬件，而本仓库 XCTest 只能真机跑 | **写进 view model**：那就得构造 `AppState` + 硬件服务才能测一句关键词匹配 |

---

## 边界情况（每条都要有对应测试）

| 情况 | 期望行为 |
|---|---|
| 无进行中订单时问任何问题 | 「当前没有进行中的预约」+ 可问清单 |
| `PENDING_MATCH` 时问距离 | 「还没有志愿者接单，所以暂时算不出距离。当前是系统派单中。」（状态名一律取 `displayName`，不另写一套叫法 —— 原文档这里写的「等待匹配」在 App 里不存在） |
| `IN_PROGRESS` 时问距离 | 已经在一起跑了，距离无意义 → 说清并给当前状态 |
| 有志愿者但坐标**过期**（超 `peerFreshness`） | 当作没有坐标，说清「暂时收不到志愿者位置」+ 当前状态，**不许念旧距离** |
| `volunteerPhone` 为 nil 或状态不 `offersVolunteerCall` 时说「打电话」 | 说清现在还不能打电话及原因，**不拨号** |
| 复述号码后用户说「不用了」/ 静音超时 | 不拨号，回到普通状态，播报「已取消拨号」 |
| 说「取消订单」 | `blockedDestructive` → 「取消需要在屏幕上确认，请找取消订单按钮」 |
| 识别结果为空（没说话） | 走 `SpeechInputStopReason.silenceTimeout(hadDetectedSound: false)` 的既有播报，**不要**当成 unrecognized 念整段 |
| 麦克风/语音识别未授权 | `startRecognition` 已有播报（`:449` / `:459`），不要再叠一层自己的错误文案 |

---

## 验收

### 1. 单测（新建 `blindRunTests/VoiceStatusQueryTests.swift`）

必须覆盖：四个意图各至少 3 种说法命中、`blockedDestructive` 命中「取消」、
`unrecognized` 时 `speech` 以 `askableHint` 结尾、上面「边界情况」表的每一行。

```bash
scripts/device-test.sh -only-testing:blindRunTests/VoiceStatusQueryTests
```

**通过判据**：脚本报出的 `Test case` 计数 **> 0** 且 failed = 0。
`passed=0 failed=0` **一律当失败查**（设备锁屏 / `-only-testing` 名字打错 / 测试目标没编出来
都长这样）。

### 2. 回归（改了 `SpeechInputField` 枚举，覆盖它的既有 suite 要跑）

```bash
scripts/device-test.sh -only-testing:blindRunTests/VoiceOrderWizardTests -only-testing:blindRunTests/blindRunTests
```

**不必全量。** 本次没动 `SystemSpeechAudioSession` / `APIClient` / `AppState` 这类全 App
唯一出口（AGENTS.md §11「跑多大范围」）。

### 3. 编译门禁

```bash
xcodebuild -workspace blindRun.xcworkspace -scheme blindRun -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build-for-testing
```

### 4. 守卫与规格

```bash
node scripts/validate-guard.mjs && node scripts/validate-docs.mjs
```

本期**不新增 `/api/` 调用**，所以 `validate-spec-coverage.mjs` 的结果应与改动前一致；
若它开始报新路径，说明有人违反了「不做」清单里的「不碰后端 NLU」。

### 5. 人耳验证（不可省，代码读不出来）

真机开 VoiceOver，在首页与订单状态页各做一遍：

- [ ] 按「问一句」→ 听得到开始录音的提示音，且提示音结束后麦克风才真正开
- [ ] 说「志愿者还有多远」→ 只念距离那一句，**不念整段**
- [ ] 说一句无关的话 → 念整段 + 末尾听得到可问清单
- [ ] 说「打电话给志愿者」→ 听到号码复述 → 说「确认」→ 系统拨号界面弹出
- [ ] 同上但说「不用了」→ 不拨号，听到「已取消拨号」
- [ ] 播报进行中再次按「问一句」→ 上一段播报停止，新的录音正常开始（不是两段声音叠在一起）

> 为什么这一节不能省：调用点顺序参数全对也可能一声不响
> （`.record` 分类不开输出通道），只记「调过了」的替身对这类缺陷全盲。

---

## 收尾

1. 按 skill `aidrun-ship-check` 的格式输出验证结果，**贴真实输出**，没跑就说没跑。
2. `demo/docs/handoff.md`：本期**纯客户端改动，无需投递**。不要为了走流程新增条目。
3. commit：`feat: 盲人端加语音查订单状态入口`（不带 `Co-Authored-By`）。
4. push（Stop 钩子 `scripts/hooks/stop-checklist.mjs` 会拦）。
5. 收尾前跑一次 `/code-review`，并明确告诉 reviewer：**只报影响正确性或违反本 spec 的**，
   风格偏好一律当可选。

---

## 未决 / 需要人拍板

- **「问一句」按钮在首页的视觉位置**。首页主按钮「开始约跑」已经吃掉内容区大半
  （`primaryBookingHeight = 280`，`BlindRunnerHomeView.swift:386`），再加一个 64pt 按钮会把
  「重复当前状态」和位置摘要挤到首屏外。本 spec 定的是**插在 `repeatStatusButton` 之前**，
  实现时若真机上观感不对，改位置前先说一声，不要顺手调 `primaryBookingHeight`。
- **「问一句」这四个字是否最终文案**。产品没定过，实现时先用它，不要自己发挥成
  「语音助手」「小助」之类带拟人色彩的名字。
