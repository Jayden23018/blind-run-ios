# 助盲跑 AidRun · iOS 客户端技术与设计说明

**文档用途**：技术评审与讨论材料
**对应代码**：本仓库 `blind-run-ios`，分支 `feat/voice-address-candidates`
**最后更新**：2026-08-11

> **阅读提示**：本文档中的所有数字均来自对当前代码的静态统计（文件数、行数、用例数、端点数），
> **不代表最近一次测试执行结果**。测试执行状态见第 9 章，其中明确标注了哪些跑过、哪些没跑。

### 与后端技术文档的分工

助盲跑的技术说明分为两份，**互补，不重复**：

| 文档 | 范围 |
|---|---|
| **本文档** | iOS 客户端：路由、并发模型、语音管线、无障碍实现、客户端侧的安全约束、真机测试通道 |
| 后端仓库 `docs/技术设计说明.md` | 服务端：串行派单与五维评分算法、走散检测的双次确认、轨迹抽稀、WebSocket 限流、事务边界、短信三段式文案、位置三级降级 |

**两份都要看才完整的话题**（各自只讲自己那一半）：

- **订单状态机**：本文档第 5 章讲客户端的前置校验与权限分流；后端文档讲状态迁移的事务边界与并发控制。
- **求助（SOS）**：本文档 ADR-05 至 ADR-08 讲客户端的双路径、位置门槛、文案约束；后端文档讲触发即升级、通知旁路、受助者 ≠ 触发者的处理。
- **派单**：本文档只讲客户端如何接收与响应派单；**排序与过滤算法完全在后端**，见后端文档。

---

## 目录

1. [项目概况与边界](#1-项目概况与边界)
2. [系统架构](#2-系统架构)
3. [技术选型](#3-技术选型)
4. [关键设计决策](#4-关键设计决策)
5. [订单状态机](#5-订单状态机)
6. [语音下单管线](#6-语音下单管线)
7. [无障碍实现](#7-无障碍实现)
8. [安全与隐私](#8-安全与隐私)
9. [测试与质量保障](#9-测试与质量保障)
10. [工程化约束](#10-工程化约束)
11. [已知限制](#11-已知限制)
12. [可讨论的开放问题](#12-可讨论的开放问题)

---

## 1. 项目概况与边界

### 1.1 产品定位

助盲跑（AidRun）把视障跑者与陪跑志愿者匹配到一起。核心场景是**一次线下陪跑服务的完整生命周期**：预约 → 派单 → 会合 → 陪跑 → 结束 → 评价，以及贯穿其中的安全保障。

产品的特殊性在于**主要用户看不见屏幕**。这一条约束会向下传导到几乎每一个技术决策——它决定了播报时机、朗读顺序、失败处理方式，甚至决定了"什么时候宁可不做"。

### 1.2 仓库边界

本仓库**只有 iOS 原生客户端**。后端是仓库外的独立服务：

| 项目 | 值 |
|---|---|
| HTTP 端点 | `http://47.114.113.171` |
| WebSocket 端点 | `ws://47.114.113.171` |
| 契约唯一源 | 后端仓库 `docs/api_spec.yaml` |

服务端地址在 App 内**不可配置**，仓库内不允许出现第二个真实服务端地址。这条约束由静态守卫脚本强制。

### 1.3 代码规模

| 指标 | 数值 |
|---|---|
| 主代码 Swift 文件 | 66 个 |
| 主代码行数 | 30,050 行（其中进程内 Mock 占 2,494 行） |
| 测试文件 | 21 个 |
| 测试代码行数 | 16,554 行 |
| 测试用例（`func test`） | 650 个 |
| 调用的后端 REST 端点 | 59 条 |
| 测试代码 / 主代码比 | 约 0.55 |

### 1.4 功能范围

**已实现**：

- 手机号 + 短信验证码登录，双角色（视障跑者 / 志愿者）
- 视障跑者：实名认证、紧急联系人管理、语音下单、表单下单、订单跟踪、语音状态查询、评价、
  首次使用引导、常用出发地点（纯本地）、预计结束时间与逾期提醒、行程分享给家人（短信 / 实时位置链接）
- 志愿者：三步注册（身份核验 → 活体认证 → 资质审核）、系统派单响应、五阶段服务流程、服务认可
  （服务次数 / 评分 / 称号）
- 双端：一键求助、实时位置共享、路线摘要、账号生命周期（退出/注销）

**明确不做**（不是没来得及，是刻意不做）：

- 给视障跑者的路线导航——引导由志愿者本人完成，App 不朗读转弯提示
- 支付
- "现在就跑"——所有预约必须提前 ≥30 分钟

---

## 2. 系统架构

### 2.1 分层

```
┌──────────────────────────────────────────────┐
│  View (SwiftUI)                              │  只负责渲染与交互
├──────────────────────────────────────────────┤
│  ViewModel (@MainActor, ObservableObject)    │  持有状态、发起调用
├──────────────────────────────────────────────┤
│  AppState (全局单例)                          │  token / currentUser / activeRole
│  ├── APIClient           REST               │
│  ├── WebSocketService    实时                │
│  ├── AppRealtimeCoordinator  事件分发         │
│  ├── EmergencyCoordinator    求助状态机       │
│  └── LiveEscortSessionCoordinator  位置共享   │
├──────────────────────────────────────────────┤
│  平台能力                                     │
│  LocationService / SpeechService(TTS)        │
│  SpeechInputService(STT) / AMap SDK          │
└──────────────────────────────────────────────┘
```

### 2.2 根路由

`ContentView` + `ContentRootRouter` 持有唯一挂载的根目的地，共 8 个路由状态：

```
restoringAccount → unauthenticated → roleSelection
                                        ├→ blindProfile  → blindHome
                                        └→ volunteerProfile → volunteerHome
                                     recoveryFailed（可重试/退出登录）
```

**设计要点**：资料水合（profile hydration）是**原子提交**的——登录页、资料页、首页和高德地图实例不会在路由过程中重叠存在。地图 SDK 的重复初始化在早期版本造成过问题，这是根因修复。

路由器用一个单调递增的 `generation` 计数 + token/userID/role 四重校验（`isCurrent`）判断响应是否过期：

```swift
!Task.isCancelled &&
self.generation == generation &&
appState.accessToken == token &&
appState.userId == userID &&
appState.activeRole == role
```

慢响应回来时如果用户已经切了角色或退出登录，结果会被丢弃而不是覆盖新状态。

### 2.3 实时通道：双路径互为兜底

| 通道 | 用途 | 频率 |
|---|---|---|
| WebSocket | 派单、状态变更、位置更新、通知、求助告警 | 事件驱动 |
| REST 轮询 | 盲人端订单详情兜底 | 5 秒 |
| 补拉 | `/api/notifications/since` 断线后补齐 | 重连时 |

**为什么保留轮询**：WebSocket 在移动网络下会断，而对看不见屏幕的用户来说"状态卡住不动"没有任何视觉线索可以察觉。5 秒轮询是明确的冗余成本换可靠性。

WebSocket 消息类型（上行 2 类 / 下行 8 类）：

- 上行：`LOCATION_UPDATE`、`PING`
- 下行：`VOLUNTEER_LOCATION_UPDATE`、`BLIND_LOCATION_UPDATE`、`APP_NOTIFICATION`、`ORDER_STATUS_CHANGED`、`EMERGENCY_RESOLVED_BY_VOLUNTEER`、`PONG`、`NEW_ORDER`、`EMERGENCY_VOLUNTEER_ALERT`

---

## 3. 技术选型

| 领域 | 选型 | 理由 |
|---|---|---|
| UI | SwiftUI（iOS 16+），必要时桥接 UIKit | 无障碍属性是一等公民；`accessibilityLabel/Hint/Value` 声明式绑定状态，不会像 UIKit 那样漏更新 |
| 架构 | MVVM | 与 SwiftUI 数据流一致 |
| 并发 | 纯 async/await | 见 ADR-01 |
| 网络 | URLSession，集中在 `APIClient` | 无第三方网络库依赖 |
| 地图/定位 | 高德 SDK（3DMap / Location / Search，NO-IDFA 版） | 国内 POI 与定位精度；NO-IDFA 版规避审核风险 |
| 实名认证 | 阿里云实人认证 SDK 2.3.50（本地 Vendor） | 活体检测能力 |
| TTS | `AVSpeechSynthesizer` | 系统原生，与 VoiceOver 共存 |
| STT | iOS `Speech` 框架 | 系统原生，中文识别质量够用，无需联网第三方 |
| Token 存储 | Keychain | 见 ADR-03 |

**第三方依赖只有两类**：高德（地图定位）和阿里云（实名认证）。网络、并发、语音、存储全部用系统能力。这是刻意的——依赖越少，iOS 大版本升级时的维护面越小。

---

## 4. 关键设计决策

以下按 ADR（Architecture Decision Record）格式记录：背景 → 决策 → 后果。这些是最值得讨论的部分。

### ADR-01：并发模型只用一种（async/await）

**背景**：SwiftUI + Combine + async/await 三套机制并存时，同一条数据流上既订阅 publisher 又 `await` 异步函数，会产生只在真机上偶现的时序 bug。

**决策**：同一条数据流不混用。ViewModel 不同时持有 `AnyCancellable` 和 `Task`。新代码一律 async/await。

**后果**：牺牲了 Combine 在某些场景的表达简洁性；换来的是时序问题可推理。这条由静态守卫强制。

---

### ADR-02：枚举遇未知值降级，不整条崩

**背景**：后端往枚举里加值而契约没同步时，客户端 `Decodable` 默认会抛错，导致**整个响应解码失败**、整页空白。

**决策**：所有对外枚举都带 `unknown` case。`RunOrderStatus`、`PacePreference`、`RoutePreference`、`EmergencyEventStatus` 均如此。

**后果**：对视障用户来说，"点了没反应"就是事故——他们没有视觉线索去判断是加载中还是崩了。宁可显示"状态未知"，也不能整页空白。

**注意方向相反的另一半**：未知**取值**要宽容降级，但解码**失败**必须留痕。两者容易混为一谈，`try?` 吞掉解码错误是本仓库识别出的一类反复缺陷。

---

### ADR-03：Keychain 用 `kSecAttrAccessibleAfterFirstUnlock`

**背景**：陪跑过程中 App 会在后台、甚至锁屏状态下读取 Token 去建立 WebSocket 连接和上报位置。

**决策**：accessibility 固定为 `kSecAttrAccessibleAfterFirstUnlock`，不用更严格的 `WhenUnlocked`；不设置 `kSecAttrSynchronizable`（不随 iCloud 同步）。

**后果**：若用 `WhenUnlocked`，锁屏时读不到 Token，**后台续跑会静默失效而不报错**——跑者把手机揣兜里，位置共享就断了，而没有任何人会知道。这是安全性与可用性的显式权衡，权衡结果写在代码注释里。

Access token **绝不写入 UserDefaults**，由静态守卫强制。

---

### ADR-04：坐标系跟随坐标流转

**背景**：设备 CoreLocation 返回 WGS-84，高德和后端用 GCJ-02。重复转换或漏转换都会造成位置偏移几百米——在会合场景下这是功能性失败。

**决策**：定义 `LocatedCoordinate`，坐标值与**坐标系来源**（`wgs84Device` / `gcj02Backend`）一起流转。转换只在唯一的网络边界 `BackendCoordinateNormalizer` 发生，后端来源坐标在这里**显式原样通过**。

**后果**：类型系统让"重复转换"变成写不出来的代码，而不是靠人记住。

---

### ADR-05：求助的双路径设计

**背景**：视障跑者首页需要一个常驻的求助入口（紧急时不能让人先去找订单），但云端求助事件必须挂在一个具体订单上。

**决策**：`BlindHomeSOSMode.resolve` 按订单状态分流：

- **`IN_PROGRESS`** → 走云端链路，`POST /api/emergency/trigger`，上报位置
- **其他任何状态** → 降级为**本地拨号**（主紧急联系人 / 110），**绝不调用云端接口**

**后果**：降级分支的文案必须说清"App 不会代你发送求助"。不说清等同于让用户以为求助已发出——按下去只有拨号音，而他们看不见屏幕上什么都没发生。逐状态由测试用例钉死。

---

### ADR-06：求助文案永不宣称已送达

**背景**：后端的 `EMERGENCY_CONTACT_NOTIFIED` 事件是在触发事务**内**同步推送的，而短信是事务提交**后**异步发的；短信发送失败只通知客服，**从不回告用户**。

**决策**：iOS 用自己的**进行时**文案覆盖后端的完成时态：

> 系统正在联系你的紧急联系人，尚未确认对方是否收到。

只有在收到明确的送达事件后，才播报"已收到求助短信"。字符串"联系人已收到短信"不得出现在发布产物中，由静态守卫强制。

**后果**：这是一条**产品伦理约束写进构建门禁**的例子。让一个处于危险中的人误以为家人已经知道了，比不告诉他更危险。

---

### ADR-07：求助必须带真实位置，宁可不发

**背景**：后端技术上接受无 GPS 的降级提交。

**决策**：客户端把这条路关着——`EmergencyCoordinator.allowsSubmissionWithoutLocation = false`。拿不到新鲜的真实 GCJ-02 坐标就**不发送**，并同时用**文字和语音**告知用户，引导改打 110。Mock / demo 坐标绝不上传。

**后果**：一条没有位置的求助对救援没有价值，却会让用户以为已经求救成功。宁可让他立刻知道失败。

---

### ADR-08：志愿者不得拥有"误触"撤销权

**背景**：一对一陪跑场景中，志愿者可能就是威胁来源。

**决策**：撤销权只在**受助者本人**（`PUT /api/emergency/{id}/cancel`）和平台客服手里。后端对志愿者撤销一律返回 403。志愿者能做的只有「确认需要帮助」。

**后果**：这是威胁模型驱动的权限设计，不是功能疏漏。

---

### ADR-09：`IN_PROGRESS` 不展示取消入口（对盲人端）

**决策**：盲人只能取消 `PENDING_MATCH` / `PENDING_ACCEPT` / `REMATCHING`。服务进行中不提供取消。

**后果**：服务已经开始时，用户需要的是求助或沟通，不是取消订单。取消入口在这个阶段是误触风险而非功能。

---

### ADR-10：地图在朗读顺序中排最后

**决策**：辅助地图标注为"仅用于视觉确认，不能操作"，且在 VoiceOver 遍历顺序中排在状态和主要操作**之后**。

**后果**：屏幕阅读器用户不必穿过一个对他们无用的大控件才能听到关键信息。地图服务的是低视力用户和陪同者，不是全盲用户。

---

### ADR-11：语音确认轮"本地直通 + 后端兜底"

**背景**：确认轮的意图判定如果只走后端，断网时整个确认流程不可用；如果只走本地，词表覆盖不全。

**决策**：常用意图（确认 / 重说 / 重复）在本地直接判定，其余走后端 NLU。

**风险与对策**：同一句话由两处判定，本地表里出现一个后端判成**别的**意图的词，就会让有网 / 断网行为分叉。直接起因是"再说一次"——前端判「重说」（清空整句），后端判 `REPEAT`（只重念）。现在有一条门禁脚本 `validate-voice-intent-words.mjs` 把本地直通表与后端 `VoiceSlotParser` 的正则对撞校验。

---

### ADR-12：OpenAPI 生成代码只当漂移探测器，不投入运行时

**背景**：后端 spec 可以生成 Swift 客户端代码（`Packages/AidRunAPI`）。

**决策**：生成代码**不投入运行时**，运行时仍走手写 `APIClient`。生成物只用来探测契约漂移。

**理由**：生成的是**封闭枚举**。投入运行时会把 ADR-02（未知枚举值不许整条崩）这条盲人端红线直接退回去。解除条件是后端改成开放枚举。

---

### ADR-13：Combine 重放门（`CurrentValueReplayGate`）

**背景**：这是一个值得单独讲的真实缺陷。

`@Published` 是 current-value publisher，会**立即向每个新订阅者发送当前值**。而播报（TTS）会修改 `SpeechService`，这会让视图失效、重建订阅；重建的订阅立刻重放同一条通知，再次触发播报——**形成主线程渲染 / TTS 反馈循环**。

`removeDuplicates()` 挡不住，因为它只在单个订阅生命周期内有效，跨订阅重建就失效了。

**决策**：引入 `CurrentValueReplayGate`，把"上一次已处理的标识"保存在**视图状态**里，跨订阅生命周期存活：

```swift
struct CurrentValueReplayGate<Value: Equatable> {
    private(set) var lastAcceptedValue: Value?
    mutating func accepts(_ value: Value) -> Bool {
        guard lastAcceptedValue != value else { return false }
        lastAcceptedValue = value
        return true
    }
}
```

**后果**：这类缺陷在"看得见"的 App 里可能只是轻微卡顿，在语音优先的 App 里是持续重复播报，用户无法操作。

---

## 5. 订单状态机

### 5.1 状态集合（封闭，共 9 个 + 1 个未知）

```
PENDING_MATCH   PENDING_ACCEPT   IN_PROGRESS   DRIVER_EN_ROUTE
DRIVER_ARRIVED  COMPLETED        CANCELLED     REMATCHING       NO_VOLUNTEER
```

### 5.2 正常流转

```
PENDING_MATCH → PENDING_ACCEPT → DRIVER_EN_ROUTE → DRIVER_ARRIVED → IN_PROGRESS → COMPLETED
```

### 5.3 取消流转（按 token 角色区分权限）

```
PENDING_MATCH / PENDING_ACCEPT              →  CANCELLED    （盲人 token）
PENDING_ACCEPT / DRIVER_EN_ROUTE /
DRIVER_ARRIVED / IN_PROGRESS                →  REMATCHING   （志愿者 token）
REMATCHING                                  →  CANCELLED    （只能盲人 token）
```

`REMATCHING` 之后只有盲人能取消——**那个志愿者已经不是订单参与者了**。这是权限设计而非流程遗漏。

### 5.4 状态流转端点

统一为 `POST /api/orders/{orderId}/{action}`：

| action | 触发方 | 前置状态 |
|---|---|---|
| `respond`（体带 `ACCEPT`/`DECLINE`） | 志愿者 | PENDING_ACCEPT |
| `en-route` | 志愿者 | PENDING_ACCEPT |
| `arrived` | 志愿者 | DRIVER_EN_ROUTE |
| `start-service` | 志愿者 | DRIVER_ARRIVED |
| `finish` | 志愿者 | IN_PROGRESS |
| `cancel` | 双方（权限见上） | 见上 |

客户端对每个动作的前置状态都做本地校验，并给出**具体原因**而非通用错误，例如"当前订单状态尚未到达约定地点，不能开始服务"。

### 5.5 求助不是订单状态

`POST /api/emergency/trigger` 只记录事件，**订单状态不变**。求助有自己的独立状态机（`PENDING` / `VOLUNTEER_NOTIFIED` / `VOLUNTEER_CONFIRMED` / `CS_HANDLING` / `CONTACT_NOTIFIED` / `RESOLVED` / `FALSE_ALARM`）。

历史上"emergency"曾被当作订单状态，现在是被静态守卫拦截的禁用词之一。

---

## 6. 语音下单管线

这是产品最有特色的部分，也是技术上最复杂的部分。

### 6.1 设计目标

让视障用户**一句话完成下单**，而不是在表单里逐字段填写。表单对看不见的人来说意味着大量的焦点移动和状态记忆负担。

### 6.2 三阶段状态机

```
freeform（自由说）
     ↓  POST /api/orders/voice/parse
[disambiguateStart]（地点消歧，仅在需要时）
     ↓  POST /api/orders/voice/resolve-address
confirm（确认轮）
     ↓  POST /api/orders/voice/parse-slot  或本地直通
提交订单
```

### 6.3 各阶段行为

**freeform**：一句话说出出发地、时间、时长等。**唯一必须的槽位是预约时间**——没有时间不能下单，因为默认一个时间是危险的（用户可能以为约的是另一个时刻）。

**disambiguateStart**：同名地点候选，读出编号列表，用户回答"第一个/第二个/第三个"。词表包含变体（"第1个"、"第一"、"头一个"）。连续没听清时**降级取第一个**，并**明确告知**："没听清是第几个，先按第一个来。"

**confirm**：复述全部内容后接受四类输入——确认、整句重说、重复念一遍、单槽位修改（"时间改成明天早上九点"）。单槽位修改覆盖 7 个槽位：出发地、结束地、开始时间、时长、导盲犬、配速、备注。

### 6.4 降级策略（关键）

任何一条失败路径都**必须说明原因**再降级，不能静默：

| 触发条件 | 行为 |
|---|---|
| 语音识别启动失败 | 播报原因 → 切表单 |
| 连续 2 次没听到预约时间 | 播报原因 → 切表单 |
| 同一槽位连续 3 次没听清 | 播报原因 → 切表单 |
| 后端解析服务不可用 | 播报"语音下单暂时用不了" → 切表单 |
| 解析成功但内容为空 | 播报"这次没能把你说的话转成预约内容，下面念的是默认值" → 继续确认轮 |
| 地点找不到 | 播报"没找到你说的那个地点，出发地先按当前位置来" → 继续 |
| 时长超出可选范围 | **钳制到最接近值** + 播报实际采用值 |

**共同点**：降级永远伴随播报。对看不见的用户，静默降级 = 系统行为不可知。

### 6.5 语音输入层（`SpeechInputService`）

| 机制 | 实现 |
|---|---|
| 音频会话 | `.playAndRecord` + `.duckOthers` + `.defaultToSpeaker` |
| 录音起止提示音 | 程序合成的双音符 WAV（起始 660→990 Hz，结束 880→587 Hz，每段 0.11 秒） |
| 停止原因 | `manual` / `finalResult` / `silenceTimeout(是否检测到声音)` / `maxDuration` / `error` |
| 输入场景 | 13 个具名场景（`SpeechInputField`），各自独立的超时与提示策略 |

**为什么用合成音而非音频文件**：起止提示音是唯一告诉用户"现在开始录了 / 已经停了"的信号。程序合成保证音色一致、不受资源丢失影响，且能精确控制时长。

**踩过的坑**：音频分类设置错误（如用 `.record`）时，调用点顺序参数全对，但**一声不响**。只记录"调用过了"的测试替身对这类缺陷完全失明——断言必须打在运行时会话状态上。修改音频分类属于全局改动，影响每个用麦克风的位置。

---

## 7. 无障碍实现

### 7.1 硬性规则

| 规则 | 实现 |
|---|---|
| 主操作触达尺寸 | `minHeight: 64`（远超 Apple HIG 的 44pt） |
| 次级操作 | `minHeight: 52` |
| 图标按钮 | `44×44` 或 `64×64` |
| 每页必有"重复当前状态" | 首页、下单、订单状态、引导页、志愿者服务页均有 |
| 朗读顺序 | 状态 → 主操作 → 次操作 → 地图（最后） |
| 二次确认 | 求助、取消订单、拨号、退出登录、删除账户 |
| 不依赖视觉线索 | 所有 `accessibilityLabel` 自带完整语义，不说"上面的按钮" |

### 7.2 `accessibilityLabel` 的写法

标签不只是控件名，而是**控件名 + 当前状态**：

```swift
.accessibilityLabel("盲人跑者首页。\(viewModel.currentStatusText)")
.accessibilityLabel("实名认证，当前状态\(appState.blindIdentityStatus.displayName)")
.accessibilityLabel("当前订单：\(order.status.displayName)，预约时间 …，出发地点 …")
```

`accessibilityHint` 说明**后果**而非操作：

```swift
.accessibilityHint("点击后进入语音下单：说一句想什么时候跑、跑多久，听完复述再确认。也可以改用表单填写")
```

### 7.3 TTS 与 VoiceOver 共存

App 主动播报（`SpeechService`）与 VoiceOver 朗读并行存在。这带来两个必须处理的问题：

1. **重复播报**——由 ADR-13 的重放门解决。
2. **播报与录音抢音频会话**——由 `SpeechInputService` 的分类切换管理（录音用 `.playAndRecord`，播报用 playback 分类）。

### 7.4 无障碍的自动化验证

`AccessibilityAuditTests.swift`（12.3 KB）对可访问性属性做断言。但**自动化只能覆盖结构性问题**（缺 label、触达过小），朗读顺序是否合理、文案是否听得懂，仍然需要真人用 VoiceOver 走一遍。

---

## 8. 安全与隐私

### 8.1 认证

- JWT Bearer Auth，token 存 Keychain（见 ADR-03）
- 无密码，手机号 + 6 位短信验证码
- 会话恢复失败时提供"重试恢复"和"退出登录"两条明确出路，不静默失败

### 8.2 退出登录的诚实处理

服务端撤销失败时，App **不假装退出成功**，而是给出三个选项：重试 / 仅退出本机 / 取消。选择"仅退出本机"时明确告知：

> 当前无法确认服务端 Token 已撤销。仅退出本机会清除本机登录信息，但远端 Token 可能继续有效。

### 8.3 信息最小化

- 志愿者**接单前**看不到视障跑者的联系方式、紧急联系人、敏感健康信息
- **接单后**展示掩码号码（`138****1001`）并给出拨号按钮；全号只进 `tel:`，
  不上屏、也不进 `accessibilityLabel` —— VoiceOver 外放，念全号等于把号码广播给周围所有人
- 紧急联系人列表中电话号码同样以掩码形式展示（`maskedPhone`）

### 8.4 密钥管理

- 高德 API key 只能来自本地配置文件 `LocalConfig.xcconfig`（已 gitignore），提供 `.example` 模板
- 不硬编码、不提交真实 key，由静态守卫强制

### 8.5 网络诊断

`NetworkDiagnosticRecorder`（actor，容量 50 条环形缓冲）记录请求阶段（response / transportFailure / decodingFailure / cancelled），用于诊断"看不见屏幕的用户报告说没反应"这类问题。

---

## 9. 测试与质量保障

### 9.1 测试构成

| 测试文件 | 规模 | 覆盖 |
|---|---|---|
| `blindRunTests.swift` | 277 KB | 主干单元测试 |
| `VoiceOrderWizardTests.swift` | 135 KB | 语音下单状态机 |
| `blindRunUITests.swift` | 78 KB | UI 端到端 |
| `LiveEscortTrackTests.swift` | 32 KB | 位置共享与路线 |
| `EmergencySOSTests.swift` | 31 KB | 求助逐状态验证 |
| `AppRealtimeCoordinatorTests.swift` | 46 KB | 实时事件分发 |
| `VoiceStatusQueryTests.swift` | 19 KB | 语音状态查询 |
| `EmergencyContactsViewModelTests.swift` | 16 KB | 紧急联系人规则 |
| `OrderEnumLeniencyDecodingTests.swift` | 15 KB | 枚举宽容解码（ADR-02 回归） |
| `AccessibilityAuditTests.swift` | 12 KB | 无障碍属性审计 |
| `ContractFixtureTests.swift` | 10 KB | 真实响应 fixture 回归 |
| 其余 10 个 | — | Keychain、法律链接、通知补拉等 |

**合计 650 个用例、16,554 行。**

### 9.2 测试执行状态（诚实说明）

> **本次未执行测试。** 上述数字是对代码的静态计数，不是执行结果。
>
> 本仓库的 XCTest **只能在真机上跑**——高德 SDK 不含 arm64 模拟器切片，
> 而 CI runner 只有模拟器。CI 做的是 `build-for-testing` 编译门禁 + 规格校验，**跑不了任何 XCTest**。
>
> 真机测试通道：`scripts/device-test.sh`（先探活、锁屏立即失败、按 result bundle 统计用例数）。
> 全量约 10 分钟。
>
> **零执行一律当失败查**：`passed=0 failed=0` 可能是设备锁屏、`-only-testing` 名字打错、
> 或测试目标没编出来——命令返回成功但一条断言都没跑。脚本对此有硬失败。

### 9.3 契约门禁

前端不持有契约副本，契约唯一源在后端仓库。pre-push 钩子共跑 9 条校验，分两类。

**读后端契约的 4 条**（对撞前后端）：

| 脚本 | 校验内容 |
|---|---|
| `validate-spec-coverage.mjs` | 前端调的每条 `/api/` 路径都在后端 spec 里存在 |
| `validate-error-codes.mjs` | 前端 `ErrorCode` 枚举 vs 后端 `ErrorCode.java` |
| `validate-golden-corpus.mjs` | 语音黄金语料 vs 前端镜像清单 |
| `validate-voice-intent-words.mjs` | 确认轮本地直通表 vs 后端 `VoiceSlotParser` 正则（见 ADR-11） |

**本仓库自测的 5 条**：`validate-docs`（文档一致性）、`validate-guard`（守卫自测）、`validate-stop-checklist`、`validate-session-context`、`validate-xcresult-verdict`（真机测试判定自测）。

读后端那 4 条跑在三处，**结论强度不同**：

| 位置 | 状态 | 说明 |
|---|---|---|
| 本地 pre-push | 真跑 | 读后端仓库工作区，push 前自动 |
| fork CI | 真跑 | 配了只读 PAT |
| 上游 CI | **warning 空过** | 无 admin 权限配不了 secret，**上游 CI 绿 ≠ 契约对过了** |

---

## 10. 工程化约束

这部分是把"反复犯的错"变成机器检查，可能是本项目在工程方法上最值得讨论的一点。

### 10.1 事故复盘规则

项目有一条硬规则：**任何犯过第二次的错误，或单次耗掉三次以上尝试才做对的东西，必须落到四者之一**：

1. 能被静态检查抓到 → 加一条守卫（`scripts/hooks/guard.mjs`）
2. 能被运行时检查抓到 → 加一条测试（优先真实响应 fixture 回归）
3. 能被"该做没做"抓到 → 加进 Stop 钩子（`scripts/hooks/stop-checklist.mjs`）
4. 三者都不能（纯语义认知）→ 写进项目记忆并索引

**只写文档不算完成**——文档挡不住重复犯错，这条规则的存在本身就是因为它已经被证明挡不住。

### 10.2 静态守卫覆盖的规则

`guard.mjs` 作为 PreToolUse 钩子拦截编辑动作，共 **11 条规则**，自测 `validate-guard.mjs` **28 条用例**（CI 与 pre-push 都跑）：

| 规则 id | 拦什么 |
|---|---|
| `legacy-status` | 禁用的遗留订单状态词（`submitted`/`matching`/`accepted`/`arrived`/`emergency` 等） |
| `sos-copy` | 宣称短信已送达 / 家属已通知的文案（ADR-06） |
| `server-addr` | 除 `47.114.113.171` 外的真实服务端地址 |
| `archived-contract` | 读取已归档的旧契约副本 `docs/_archive-*.bak` |
| `frozen-files` | `Podfile` 整文件；`project.pbxproj` 的 `DEVELOPMENT_TEAM` 行；任何文件的架构排除键 |
| `amap-key` | 硬编码的 32 位十六进制高德 key |
| `openapi-in-app-target` | OpenAPI 运行时 `import` 进 App target（ADR-12 的配套约束） |
| `weak-temporary` | 把当场构造的临时对象传给 `weak` 依赖 |
| `blind-tap-center` | UI 测试里敲屏幕正中（绕过真实控件的假通过） |
| `secrets-in-if` | workflow 的 `if:` 表达式里用 `secrets` |
| `missing-team` | 脚本里调 xcodebuild 真机动作却没传 `DEVELOPMENT_TEAM` |

每条规则都有行内豁免口（`// guard:allow <rule-id>`），且纯注释行不拦——引用后端的坏文案来解释"为什么要覆盖它"恰恰是应该留在代码里的。

其中 `weak-temporary` 值得单说：View model 的依赖清一色是 `weak var`（避免与 View 循环引用）。传一个当场构造的临时对象进去，出了那一行就没人持有它，属性立刻变 `nil`，**而测试照样绿**——它只是没在测你以为在测的那件事。`BlindBookingGateTests` 里有一条断言就这么"过"了很久，直到把对象 `let` 住才发现它从来没碰过 `LocationService`。

### 10.3 Stop 钩子

工作树脏或领先 origin 时拦住会话结束并列出欠账。两条防噪音约束：一次停止只拦一次；同一份欠账只提醒一次（签名存在 `.git/` 下）。

### 10.4 OpenSpec 变更管理

行为变更前先写规格。当前有 8 个未归档变更：

`capture-and-gate-runner-extra-needs`、`capture-order-end-location`、`complete-blind-profile-and-contacts`、`disambiguate-same-name-start-place`、`enable-cross-turn-voice-correction`、`enable-independent-sos-safely`、`enable-live-escort-location-and-track-summary`、`enable-one-utterance-booking`

**已知问题**：`openspec validate --strict` 只查结构不查语义。同一变更里 proposal / design / tasks / specs 四份 artifact 已经出现过三次反向漂移——改实现方向时四份必须一起过。

---

## 11. 已知限制

诚实列出，避免演示时被问到才发现：

| 限制 | 影响 | 状态 |
|---|---|---|
| CI 跑不了任何 XCTest | 回归依赖本地真机执行的纪律 | 高德 SDK 无 arm64-sim 切片，**永久性** |
| 模拟器通道不可用 | 同上 | 同上 |
| 无 GPS 时求助被禁止 | 极端情况下无法发起云端求助 | 刻意关闭（ADR-07），需产品/安全批准才开 |
| 志愿者无实质激励 | 只有服务次数 / 评分 / 称号，无兑换、无优先派单 | 「积分 +100/次」那版是客户端把单数乘 100 显示，已移除 |
| 无支付 | — | 范围外 |
| 无路线导航（盲人端） | 引导完全依赖志愿者 | 刻意不做 |
| OpenAPI 生成代码不投运行时 | 契约变更仍需手工同步 `APIClient` | 待后端改开放枚举（ADR-12） |
| 上游 CI 的契约门禁 warning 空过 | 上游 CI 绿不能作为契约正确的依据 | 无上游 admin 权限，配不了 secret |
| 8 个 OpenSpec 变更未归档 | 需确认它们没有 delta 同一个能力，否则规格打架 | 待整理 |
| `try?` 吞掉解码错误 | 已修 2 处（REST 分页、WS 解码），仍有一批未修 | 进行中 |

---

## 12. 可讨论的开放问题

以下是我认为值得听取意见的方向：

### 12.1 语音交互

1. **一句话下单的槽位边界**：当前只强制"预约时间"必填，其余走默认。是否应该也强制出发地点？默认取当前位置在跑者已经出门在路上时可能是错的。
2. **消歧降级取第一个**：连续听不清时取第一个候选并告知。另一种设计是直接切表单。哪种对用户更好，目前没有实测数据支撑。
3. **本地直通词表的维护成本**：ADR-11 的双判定方案需要一条门禁脚本长期维护。是否值得？替代方案是全部走后端（断网不可用）或全部走本地（覆盖不全）。

### 12.2 安全设计

4. **无 GPS 时禁止求助**是否过于严格？当前宁可不发，引导打 110。反方观点是：有位置的求助固然更好，但没位置的求助至少让平台知道有人出事了。
5. **求助冷却时间**：防重复提交与紧急情况下的重试需求冲突。当前冷却期间只能打电话。

### 12.3 工程方法

6. **测试代码 / 主代码比 0.55**（16.5k / 30k 行）。650 个用例中相当一部分是状态机穷举。这个投入产出比是否合理？
7. **"事故必须落到机器检查"这条规则**——它明显提高了单次改动的成本（每个坑要写守卫或测试），换来的是同类错误不再复发。这是我最想听意见的一条方法论。
8. **真机唯一测试通道**是 SDK 限制的结果，不是选择。是否值得为了 CI 可用性替换地图 SDK？

### 12.4 产品

9. **系统派单 vs 抢单**：当前是系统派单 + 倒计时响应。抢单模式响应更快但可能导致偏远地区无人接单。
10. **志愿者激励**：只有服务次数 / 评分 / 称号，没有兑换、没有优先派单。
    （此前那版「积分 +100/次」是客户端拿完成单数乘 100 显示出来的，后端从未下发过积分，已移除。）
    可持续性存疑 —— 陪跑平台每位视障跑者需要 6–8 名固定陪跑员，志愿者供给是生死线。

---

## 附录 A：关键文件索引

| 关注点 | 文件 |
|---|---|
| 根路由与水合 | `blindRun/ContentView.swift` |
| 全局状态 | `blindRun/Core/AppState.swift`（789 行） |
| 网络层 | `blindRun/Core/APIClient.swift`（470 行） |
| 实时事件分发 | `blindRun/Core/AppRealtimeCoordinator.swift`（1145 行） |
| WebSocket | `blindRun/Core/WebSocketService.swift`（581 行） |
| 语音下单状态机 | `blindRun/Voice/VoiceOrderWizard.swift`（1174 行） |
| 语音输入层 | `blindRun/Voice/SpeechInputService.swift`（1011 行） |
| 求助状态机 | `blindRun/Safety/EmergencyCoordinator.swift`（452 行） |
| 求助文案与判定 | `blindRun/Safety/SafetyModule.swift`（315 行） |
| 订单模型与状态机 | `blindRun/Core/Models/OrderModels.swift`（637 行） |
| 坐标系 | `blindRun/Map/CoordinateSystem.swift`（112 行） |
| Token 存储 | `blindRun/Core/KeychainTokenStore.swift`（107 行） |
| 环境配置 | `blindRun/Core/EnvironmentConfig.swift`（105 行） |
| 志愿者服务流程 | `blindRun/Volunteer/VolunteerOrderFlowViews.swift`（2727 行） |
| 进程内 Mock | `blindRun/Core/MockAPIClient.swift` + `MockAPIClient+{Auth,Profile,Incentive,EmergencyContact,Order,IntroCall,Voice}.swift` |
| 领域 service 层 | `blindRun/Core/Services/`（当前只有 `AuthService.swift`）+ `blindRun/Core/Endpoints/EndpointRequest.swift` |

## 附录 B：验证命令

```bash
# 编译门禁（无真机时的上限）
xcodebuild -workspace blindRun.xcworkspace -scheme blindRun \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build-for-testing

# 真机测试（唯一 XCTest 通道）
scripts/device-test.sh

# 只跑受影响的 suite（推荐，全量约 10 分钟会超时）
scripts/device-test.sh -only-testing:blindRunTests/VoiceOrderWizardTests

# 契约与规格校验
openspec validate --all --strict --no-interactive
node scripts/validate-spec-coverage.mjs
node scripts/validate-error-codes.mjs
node scripts/validate-golden-corpus.mjs
node scripts/validate-voice-intent-words.mjs
```

---

*本文档描述当前代码的实际实现。所有设计决策的理由均来自代码注释、项目约束文档或提交历史，未作推测。*
