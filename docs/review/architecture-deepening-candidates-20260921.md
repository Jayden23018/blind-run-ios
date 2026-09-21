# 架构加深候选清单 —— 全仓勘察（2026-09-21）

用 `improve-codebase-architecture` skill 做的一轮全仓架构审查。方法：3 个 Explore subagent
分头收集事实（状态与并发层 / 订单流 View 层 / 网络与契约层），**结论一律由主会话自己复核**
—— 下面 §1 两条就是复核推翻的。

本轮落地：PR #173（候选 A + D）。其余候选留在 §3，没做。

---

## §0 引用前必读：两条被证伪的候选

**这一节是本报告最该先读的部分。** 两条都「看起来像大问题」、都**直接撞上本仓库已知红线**，
而两条都不成立。记忆 `reviewer-numbers-that-match-a-red-line` 说的就是这种形态：
危险的不是可疑发现，是方向正好撞上红线的那种 —— 认同感会替代核实。

### ❌ 证伪一：「12 个枚举缺 unknown 兜底，会把整页解崩」

subagent 报：`Models/` 下 21 个 `enum ... : String, Codable` 里 12 个既无 `case unknown`
也无自定义 `init(from:)`，点名 `UserRole` / `ErrorCode` / `WSMessageType` / `VisionLevel` 等。
这**逐字撞上** `CLAUDE.md` 的红线「枚举解码遇未知值不许整条崩……对盲人端『点了没反应』就是事故」。

**不成立。判据是「这个枚举有没有被当成解码属性的类型」，不是「它有没有 case unknown」。**
逐个查了所在结构体：

| 枚举 | 所在类型 | 实际情况 |
|---|---|---|
| `UserRole` | `SetRoleRequest` | 请求体，只编码 |
| `OrderRespondAction` | `OrderRespondRequest` | 请求体 |
| `VoiceSlotField` | `ParseSlotRequest` | 请求体 |
| `SupportTicketCategory` | `SupportTicketRequest` | 请求体 |
| `LocationSource` | `LocationPoint` | 连 `Codable` 都不是，只有 `Sendable` |
| `EmergencyEventStatus` | `ActiveEmergencyEvent` | App 内部类型，不解码 |
| `VisionLevel` / `TetherPreference` / `ChatPreference` | — | 后端值以裸 `String` 存下，用 `Enum(rawValue:)?` 转，未知值天然降级 |
| `WSMessageType` | — | 只取 `.rawValue`；WS 解码走 `WSIncomingEvent`，它有 `case unknown(String)` |
| `ErrorCode` | `ErrorResponse` | `var errorCode: ErrorCode?` 是**计算**属性，裸串存储 |
| `IntroCallDecision` | — | 同上，`myDecisionValue` 是计算属性 |

**真实状态：这条红线已经被架构性地兜住了，而且有两套一致的做法** ——
直接解码的 8 个用 `case unknown` + 自定义 `init(from:)`（`RunOrderStatus` 是范本，
`OrderModels.swift:58` 那段注释把理由写得很清楚）；其余用「存裸串 + 可选计算属性」。

唯一的真实瑕疵是 `EmergencyEventStatus` 有 `case unknown` 却没有自定义 `init(from:)`
（兜底不生效），但它的使用点已经绕开它改用裸 `String`，`OrderModels.swift:828-833`
的注释写明了这个绕法及其复现过程。**没有可修的东西。**

### ❌ 证伪二：「7 个 `...Serving` protocol 各自只有一个实现，是空壳」

按本 skill 的判据「一个 adapter = 假想接缝，两个 adapter = 真接缝」，单实现 protocol
是典型的浅模块。subagent 报 7 个全部单实现。

**不成立 —— 它只搜了 `blindRun/`，没搜 `blindRunTests/`。** 全仓（含测试）重搜：

| protocol | 实现数 | 第二个实现 |
|---|---|---|
| `AuthServing` | 2 | `blindRunTests/FakeAuthService.swift:14` |
| `IncentiveServing` | 2 | `blindRunTests/FakeIncentiveService.swift:15` |
| `OrderServing` | 2 | `blindRunTests/FakeOrderService.swift:17` |
| `SafetyServing` | 2 | `blindRunTests/FakeSafetyService.swift:13` |
| `ProfileServing` / `TrainingServing` / `VoiceOrderServing` | 1 | 改从 transport 层测 |
| `APIClientProtocol` | **28** | 25 个测试桩 + `DisabledAPIClient` + `MockAPIClient` |

测试替身就是第二个 adapter。这几条是**真接缝**，删掉它们复杂度会在多处重现。

> 方法论一句：判「某个东西只有一个实现」时，搜索范围必须含测试目录。
> 少搜一个目录得出的是一个**方向完全相反**的架构结论。

---

## §1 已落地（PR #173）

### 候选 A｜订单状态判定有三种写法，只有一种会在加状态时报警

全仓 69 处状态判定：

| 写法 | 处数 | 后端加状态时 |
|---|---|---|
| 穷举 `switch` | 39 | 编译失败，逼一次决策 |
| 带 `default:` 的 `switch` | 13（9 处在 `OrderModels.swift` 自己身上，含 `isTerminal`）| 静默答 false |
| 数组字面量 `.contains` | 17 | 静默答 false |

17 处字面量里 **11 处是合法迁移表**（`AppRealtimeCoordinator.isDirectlyFollowed` ×7、
`VolunteerOrderFlowViews.satisfiesVolunteerTransition` ×4）—— 每一行已被外层 switch 穷举过，
字面量在那儿是对的形状。剩 6 处是真·概念字面量：

| 位置 | 概念 | 处置 |
|---|---|---|
| `LiveEscortSessionCoordinator.swift:101` | 陪跑会话该不该跑 | → `runsLiveEscortSession` |
| `LiveEscortSessionCoordinator.swift:140` | 会话该不该就地清掉 | → `endsLiveEscortSession` |
| `BlindOrderStatusView.swift:2553` | 要不要画对方地图 | → 复用 `fetchesVolunteerLocation` |
| `VolunteerOrderFlowViews.swift:2078` | 进不进服务记录 | → `appearsInVolunteerServiceRecord` |
| `MockAPIClient.swift:853` | 后端下不下发位置 | **保留字面量** + 标注 |
| `MockAPIClient+Order.swift:121` | 后端认不认为单没走完 | **保留字面量** + 标注 |

两处 Mock 保留的理由不是我想的，是仓库自己写好的（`MockAPIClient+Order.swift:114`）：
「别『顺手』换成客户端的 `isActiveForBlindRunner`……与这里问的『后端认不认为这一单还没走完』
不是同一个问题」。Mock 演后端，耦合到客户端判定会毁掉「两边不对称才被看见」这个价值。

**刻意没有做的合并**：`runsLiveEscortSession` 与 `fetchesVolunteerLocation` 今天状态集完全相同，
但没有合成一条。判据来自仓库既有先例 —— `offersWaitedDuration` 与 `offersKeepWaiting`
同样同集且刻意分开，理由写在它们自己的注释里。后端哪天只改其中一边（例如跨天预约临期
开始预热位置），合成一处就会把另一边一起改掉。

**守卫**：`guard.mjs` 新增 `status-set-literal`，判据是「字面量在不在一个 `switch` 块里」，
前向窗口走到最近的函数声明为止（真实迁移表的最后一行离 `switch` 30 行开外，
固定 N 行窗口会误报 —— 有一条用例专门钉这个）。

**不拦 `default:` 那 13 处**：判「这个 `switch` 在 switch 什么类型」需要类型信息，正则做不到；
逐个改成穷举 = 13 × 11 格产品决策，那是另一件事，不该混进这个 PR。

### 候选 D｜5 条判定零测试覆盖，其中一条有 10 个调用点

`isActiveForVolunteer`（10 调用点）/ `statusSymbolName` / `statusColor` / `sortKey` /
`blindNameForSpeech` —— 全仓测试目录 `grep` 0 命中。`isActiveForVolunteer` 是
`isActiveForBlindRunner`（有测试）的陪跑员端镜像，而两端同名判定集合悄悄错开
是本仓库栽过的事（记忆 `same-name-predicate-different-sets-across-ends`）。

已补 `blindRunTests/OrderStatusPredicateSetTests.swift`，11 条。断言一律逐态比对
**整个集合**（`RunOrderStatus.allCases` 过滤后与期望 `Set` 比），不挑几个态点名 ——
挑几个态的写法分辨不出「多了一个态」，而那正是要防的变化。

---

## §2 待拍板的一个产品决定

`runsLiveEscortSession` 对 `.unknown` 判 **false**，这是**沿用改动前的行为**，
不是重新决策过的结论。后端加了个我们还不认识的状态时，它会让陪跑途中的位置上报静默停掉。

反方向的先例就在同一个文件里：`isActiveForVolunteer` 对 `.unknown` 判 **true**，
理由是「不让订单从界面上消失」。

两难点在于「多推位置」本身也是泄露面。已记入后端 handoff 提问。**在拍板前不要顺手改那一行。**

---

## §3 没做的候选（留着，别重新发现一遍）

### 候选 B｜测试 transport 适配器太浅 —— 25 个桩重抄 1274 行

`blindRunTests/RecordingTransport.swift`（61 行）是共享替身，但它只有
`var nextResponse: Any?` —— **一个罐装响应**。凡是要「不同 path 不同响应」
「第一次失败第二次成功」「注入错误」「数调用次数」的用例都用不了它，于是各抄一遍。

实测：25 个 `APIClientProtocol` 测试桩共 **1274 行**，最大的 115 行
（`ContactsAPIClientStub`）。每个都在重抄同样三段：记流水账 / 按 method+path 路由 /
绕泛型擦除（绕法还有两种：自己写 `cast()`，或拼 JSON 字符串再 `decode(T.self)`）。
共享替身只被 6 个测试文件用到。

**为什么在这个仓库特别贵**：CI 跑不了 XCTest，每条行为都得靠本地真机用例钉住。
写一条用例贵 40 行，就会少写用例。

**修法**：把 `RecordingTransport` 加深成路由表 + 每路响应队列 + 错误注入；
存量桩不动，新用例用新的，改到的顺手换。零生产风险。

### 候选 C｜四个协调器同时持有 `AnyCancellable` 和 `Task`

直接违反 `CLAUDE.md` 硬约束「同一条数据流里不要既订阅 Combine publisher 又 `await`
async 函数；view model 不要同时持有 `AnyCancellable` 和 `Task`」。实测：

| 类型 | Combine | Task |
|---|---|---|
| `AppRealtimeCoordinator` | 3 × `AnyCancellable` | 4 × `Task` 属性 |
| `LiveEscortSessionCoordinator` | 1 × `Set<AnyCancellable>` | 4 × `Task` 属性 |
| `EmergencyCoordinator` | 1 × `Set<AnyCancellable>` | 1 × `Task` |
| `AppState` | 1 × `Set<AnyCancellable>` | sink 闭包里起 `Task` |

记忆 `terminal-status-self-cancels-the-task-doing-the-work`（零症状、纯函数用例全绿）
就是这个形态结出的果。

**本轮刻意没碰**：修法是重写实时层，而这个仓库 CI 跑不了 XCTest、真机当天离线。
高风险大改配不上「没法验证」的环境。真要做，先解决真机通道。

### 其他量到但没展开的

- `BlindOrderStatusView.swift` 3194 行 = 只有 2 个顶层类型（ViewModel 1537 行 + View 1648 行），
  内部零接缝；`VolunteerHomeViewModel` 独占 1631 行。拆分是大工程，且拆不出明显的正确边界。
- `AppState` 用 `let` 持有三个 `ObservableObject` 协调器（`:109-111`），嵌套发布不会穿透 ——
  这条已有记忆 `nested-observableobject-does-not-republish`，不是新发现。
- View 层其实是干净的：勘察报的 18 处「View 里的业务判定」绝大多数是在调
  `OrderDisplayHelpers` 上命名良好的判定，领域逻辑本来就在该在的地方。
  唯一绕过 ViewModel 直接摸 `apiClient` 的是 `BlindOrderStatusView.swift:3032`，
  在 Mock 调试区里，不是生产路径。

---

## §4 本轮的验证状态

```
node scripts/validate-guard.mjs              → 128 条通过（新增 8 条）
xcodebuild … build-for-testing               → ** TEST BUILD SUCCEEDED **  rc=0
其余 8 条本地门禁                              → 全部 rc=0
```

🔴 **真机 XCTest 未跑** —— 两台设备 `devicectl` 实测 `transportType: None` /
`tunnelState: unavailable`，`device-test.sh` 的权威输出是
`xcodebuild: error: Unable to find a destination matching the provided destination specifier`。
按 AGENTS.md §11「编译通过不等于测试通过，永远不许把没执行过的测试写成通过」，
新增的 11 条用例**一条都没执行过**。合并前必须跑：

```bash
scripts/device-test.sh -only-testing:blindRunTests/OrderStatusPredicateSetTests \
  -only-testing:blindRunTests/OrderDetailResponseSpeechAndSortTests \
  -only-testing:blindRunTests/LiveEscortTrackTests
```

⚠️ 其中 `statusColor` 那条用例有已知风险：它断言两个 `SwiftUI.Color` 相等，
而 `AppColors` 是 `dynamic(light, dark)` 构造的动态色。同一个 `static let` 比较应当成立，
但这条**从没在设备上执行过**，先跑它再信它。

**守卫部分是验过红的**：三种破坏各自打在预期的那条断言上 ——
① `withinSwitchBlock` 恒 false → 两条迁移表用例红；
② 去掉「只认订单状态」判断 → 别的枚举那条红；
③ 前向窗口改成固定 12 行 → 长迁移表那条红。还原后复跑 128 条通过。
