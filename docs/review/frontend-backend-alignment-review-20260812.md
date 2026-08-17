# 前后端对齐与前端全量 review — 2026-08-12

**落地** 初稿随 PR #20 合入 `integrate/swift-migration`；A1/A3/B1 三节在合 PR #16 时按
`git fetch` 后的事实改写过（见下方「方法上的两个坑」）。
**范围** 前后端契约对齐 / 未适配的后端能力 / UI 与无障碍 / 「列了但没做」的功能
**方法** 全部只读核查。后端事实取自 `/Users/mac/Downloads/demo` 的 `docs/api_spec.yaml`
与 `src/main/java/**`，前端事实取自本仓库源码，每条都给了可复核的 `文件:行号`。

> ⚠️ **方法上的两个坑，读本文时要知道 —— 我两个都踩了：**
>
> 1. **别读后端工作区。** 核查当时后端签出在特性分支，工作区的 `api_spec.yaml` / 语料
>    与 `origin/main` 不同。判断「后端有没有某能力」一律用 `git show origin/main:<path>`。
> 2. **`git show` 之前先 `git fetch`。** 本地的 `origin/main` 引用可能停在几小时前 ——
>    本轮 §A1 报的那个「高危缺陷」根本不存在，就是因为后端 9 小时前刚加的字段我没 fetch 到。
>
> 两条合起来才成立，只做第 1 条仍会判错。**A1 已作废、A3 改写过两次、B1 是这件事本身。**
> 其余各条已在 `git fetch` 之后对 `origin/main` 复核。

---

## 结论先行

**没有完全对齐，但比初稿判的轻。** 契约层真正成立的是 **1 个**（`addressShort` 零消费），
初稿报的另一个高危缺陷（`blindPhone`）**是我读了陈旧 ref 造成的误判，已作废**。
另有 3 类后端已交付而前端零接入的能力。

**本轮最有价值的产出不是缺陷清单，是 §B1**：五道契约门禁一直在验「后端当前签出的那个分支」
而不是契约，而它制造的是方向最坏的错误 —— 把正确的改动判成伪造。本轮实际发生两次。已修。

无障碍**架构**做得好——遍历顺序解耦、地图隐藏、「重复当前状态」全覆盖、二次确认文案逐字锁定。
但颜色对比度、横屏/iPad、Dynamic Type 上限三块基本空白，且**三者精确落在同一个用户段：低视力用户**。

「列了没做」高度集中在一处：**真机端到端验证一次都没跑过。**

---

## A. 前后端契约对齐

### A1 · ~~高~~ **已作废（我判错了）** · `blindName` / `blindPhone`

> 🔴 **本条初稿断言这两个字段是前端凭空声明的、真机上恒 nil、志愿者接单后一次都打不了盲人电话。
> 结论是错的，撤回。**
>
> 后端 `ca7c735`（2026-08-12 01:44，「把拨号断点补完整 —— 志愿者能打给盲人，客服能打给所有人」）
> 早已加齐：`origin/main` 的 `OrderDetailResponse.java` 里 `:28 blindName`、`:33 blindPhone` 都在，
> 契约里也有，且 `blindPhone` 明确是**明文可拨**（与 `volunteerPhone` 对称）。
>
> **错因：我全程没在后端仓库跑过 `git fetch`。** 手上的 `origin/main` 引用停在几小时前，
> 于是 `git show origin/main:...` 拿到的是旧快照 —— 而 `ca7c735` 比我开始 review 只早 9 小时。
> 同一个根因当天还造成了 §B1 那次误判。**教训见 §B1 末尾。**

复核后确认对得上的两件事（留档，省得下次重查）：

- 后端的拨号下发窗口 `PENDING_ACCEPT` / `DRIVER_EN_ROUTE` / `DRIVER_ARRIVED` / `IN_PROGRESS`
  （判据 `OrderStatus.allowsCounterpartCall()`）与前端
  `RunOrderStatus.offersVolunteerCall`（`blindRun/Core/Models/OrderDisplayHelpers.swift:77-90`）
  **逐态一致**，且前端写成穷举 `switch` —— 后端往枚举加值时编译器会逼一次决策，
  不会像集合字面量那样默默判 `false`。
- 后端 N52（`volunteerPhone` 曾返回掩码串 `138****1234`，客户端只取数字位 → `1381234` → 空号）
  已于 2026-08-11 修掉，现在是明文，`tel:` 拼装那条路是通的。

唯一还留着的小口子：`/api/orders/{orderId}/call/records` 的 `CallRecordResponse`
在 `components/schemas` 里没有定义。前端暂不接该端点，已在 handoff 里提了一句。

### A2 · 高 · `addressShort` / `endAddressShort` 没接，语音读回念的是完整门牌地址

后端 `api_spec.yaml:2949-2960`（2026-08-09 新增）在字段描述里逐字写着：

> `address` 的**朗读形态** —— 只有 POI 名，不含门牌号与步行指引。
> **自己拼读回文案时念这个，不要念 `address`。**

前端对 `addressShort` / `endAddressShort` **0 命中**
（`blindRun/Core/Models/VoiceOrderModels.swift` 的 `ParseVoiceOrderResponse` 未声明）。

于是读回念的是后端举的那个反例原文
`五角场市场监督管理所 国定路335号1号楼4层(国权路地铁站4号口步行110米)`，
而不是 `五角场市场监督管理所`。

读回存在的唯一意义是让盲人听出「这不是我说的地方」，他能靠听分辨的是**名字**。
这个字段就是为了修这件事加的。

### A3 · 中高 · 「问一句」的后端第 2 档 `classify-query` 前端零接入

> ⚠️ 本条改过两次，最终事实如下（前两版都因为**没 fetch 后端仓库**而判错）。

后端 `/api/orders/voice/classify-query` **已合进 `origin/main`**（`4e31766`，PR #63
`feat/voice-query-intent`）。前端零命中。

契约形状（合并后的最终版，比初版多一个字段）：

- `ClassifyQueryRequest { transcript }` —— **刻意不带 `orderId`**：本端点不读订单、不生成文案
- `ClassifyQueryResponse { intent, template }`
  - `intent`：`DISTANCE` / `STATUS` / `SCHEDULE` / `CALL_VOLUNTEER` / `OUT_OF_SCOPE`，
    **永不为 null**，判不准或任何失败一律 `OUT_OF_SCOPE`。
    用 `anyOf [enum, string]` 建成**开放枚举** —— 正合本仓库「未知枚举值不许整条崩」那条红线
  - `template`：**只有 `intent=DISTANCE` 才可能有值**，其余四类恒 `null`。
    形如 `{{VOLUNTEER}}离你还有{{DISTANCE}}，预计{{ETA}}到`，三个占位符由客户端用本地数据填 ——
    **真值不出后端**，模型只出句式，校验是「输出里一个数字都不许有」

设计上逐条对上了前端当初拒绝后端 NLU 的每个顾虑：不读订单、模型碰不到任何数字、
枚举里刻意没有「取消」、任何失败退回客户端原有兜底。

前端 `blindRun/Voice/VoiceStatusQuery.swift:10-11` 现在的理由是：

> 后端 `/api/orders/voice/parse` 在生产上恒 404 …… 按它写完，盲人拿到手的是一个恒报错的按钮。

这条理由针对的是**另一个端点**，而且 classify-query 的失败语义天生不会产生「恒报错的按钮」。
接入时这段注释要一起改掉，留着会误导下一个人。

### A4 · 中高 · 订单被自动取消前，盲人没有「继续等待」的出路

> ⚠️ **本条初稿有一句是错的，已订正。** 初稿写「`.noVolunteer` 在 15 处被当终态与
> `.cancelled`/`.completed` 同组，**要拆开**」。核实后端（`git fetch` 之后）：
> `OrderStatus.java:46` 写着 `NO_VOLUNTEER; // 超时无人接单（预留终态）`，
> `DispatchService.java:574` 也说「`NO_VOLUNTEER` 是终态」。
> **前端当终态是对的，不该拆。**

真正的缺口更窄也更要紧 —— **可恢复的窗口在订单走到 `NO_VOLUNTEER` 之前**：

- `PUT /api/orders/{id}/keep-waiting` —— `PENDING_MATCH` 下刷新匹配超时窗口
- `PUT /api/orders/{id}/keep-rematching` —— `REMATCHING` 下同理（契约明写其他状态返 409）

前端对两者 **0 命中**。而后端在放弃订单前会推 `ORDER_CANCELLATION_WARNING`（HIGH），
文案逐字是：

> 您的订单即将因长时间无人接单被取消，**点击继续等待可延长**

**后端的播报已经在教用户点一个 App 里不存在的按钮。** 盲人听到这句、屏幕上没有这个控件，
而他看不见屏幕 —— 能做的只有等订单被自动取消，再重下一单。

前端自己知道少了这块：`blindRun/Core/Models/ErrorModels.swift:20` 映射了
`KEEP_WAITING_LIMIT_REACHED`，而这个码**只有调那两个端点才可能收到**。

**去向**：已起草 openspec 变更 `offer-keep-waiting-before-auto-cancel`
（`openspec validate --strict` 通过）。注意它 MODIFY 的 Requirement 与
`enable-live-escort-location-and-track-summary` 是同一条，**必须在它之后归档**。

顺带一个待后端澄清的同名不同义：通知 `NO_VOLUNTEER_AVAILABLE` 的文案是
「您的订单**仍在等待中**」，而状态 `NO_VOLUNTEER` 是终态；
`AppRealtimeCoordinator.lifecycleStatus` 目前把该 eventType 映射成 `.noVolunteer`（用于播报去重）。

### A5 · 中 · 位置上报只有 WebSocket 一条路，REST 兜底端点没接

真实上报全部走 `WebSocketService.sendLocationUpdate`
（`blindRun/Core/LiveEscortSessionCoordinator.swift:253`、
`blindRun/Volunteer/VolunteerLocationReporter.swift:16`、`blindRun/ContentView.swift:411`）。

`/api/blind/location` 只在 `blindRun/Core/MockAPIClient.swift:372` 出现；
`/api/volunteer/location` 生产代码 0 命中。

有 generation 隔离的重连逻辑，但没有 REST 降级。`IN_PROGRESS` 期间 WS 长时间起不来
（后台、弱网），位置流就完全断了 —— 而 `ESCORT_SIGNAL_LOST` 正是后端为这个状态准备的告警。
**值不值得接是产品判断，但目前没人记录过为什么不接。**

### A6 · 中 · `CreateOrderRequest` 少三个字段

后端有、前端 `blindRun/Core/Models/OrderModels.swift` 没有：
`paceMinSecondsPerKm`、`paceMaxSecondsPerKm`、`plannedDistanceMeters`。

后果是**按距离的预约表达不出来** —— 「陪我跑 5 公里」只能折成「跑多少分钟」。
语音向导抽的三个槽位也只有起点 / 时间 / 时长。

---

## B. 工作树与门禁状态（本轮已处理）

### B1 · 高 · **契约门禁一直在验「后端当前签出的分支」，不是契约；而我自己还叠了一层「没 fetch」** ⚠️

**这条是本轮最值得落地的发现，我先后踩了两次，过程留在这里当证据。**

**第一层：门禁读工作区。** `scripts/validate-golden-corpus.mjs:26` 读的是
`../demo/docs/voice-golden-corpus.json`，即后端仓库的**工作区文件**。当时后端签出在特性分支
`feat/voice-query-intent`（从 PR #55 合并前切出，语料 96 条），而 `origin/main` 已经更多。
于是它把一份**完全正确**的语料镜像改动报成「7 条在后端语料里已不存在」，我据此 revert 掉了它。

**第二层：我自己没 fetch。** 意识到第一层之后，我改用
`git show origin/main:docs/voice-golden-corpus.json` 复核 —— **但没先 `git fetch`**。
本地 `origin/main` 引用停在几小时前（101 条），于是我判定其中 2 条「后端也没有」，把它们删了。
`git fetch` 之后是 **103 条**，那 2 条在里面，`source: regex`，期望值与原改动**逐字一致**。

**7 条全都是对的。我删了 2 条，删错。** 同一个根因还让我在 §A1 里凭空报了一个不存在的高危缺陷。

正确的复核姿势（两步缺一不可）：

```bash
git -C ../demo fetch origin main
git -C ../demo show origin/main:docs/voice-golden-corpus.json > /tmp/corpus-main.json
node scripts/validate-golden-corpus.mjs /tmp/corpus-main.json
```

**为什么这不是「注意一下」而是要落地的缺陷**：

- 受影响的是**全部五道读后端仓库的门禁**（spec-coverage / golden-corpus / error-codes /
  voice-intent-words / 生成代码比对）。后端同事切到任何分支，我们的门禁结论就跟着变，且不报警。
- 它制造的是**方向最坏的那种错误**：把正确的改动判成伪造。本轮实际发生了两次，
  第一次靠事先存了 `git diff` 才救回来。
- 「我跑了门禁，绿的」这句话在日常开发里因此是没有保证的。

**已修（本轮）**：PR #16 把契约来源改成默认 `git show origin/main:` 落临时文件。
合并时发现它自己漏了第 5 道门禁读的两个 `.java`（`VoiceSlotParser` / `VoiceOrderService`
仍直接指向工作区路径），一并补上；回归测试 `scripts/validate-prepush-contract-source.mjs`
的 fixture 从 3 份契约扩到 5 份。**但 `fetch` 那一步仍然靠人记** ——
钩子里有 `git -C "$BACKEND_DIR" fetch --quiet origin main`，手动跑脚本时没有。

> 记忆 `prepush-contract-gate-reads-backend-worktree` 曾记着「PR #16 已修掉」，
> 而 #16 当时仍是 open —— 那条记忆写于该 PR 的分支上下文，把分支行为当成了工作线现状。
> 已订正，并补上「先 fetch」这一条。

### B2 · 中 · 7 个 PR 挂着没合，最老的开了 11 天

| PR | 开启日 | 分支 |
|---|---|---|
| #2 | 08-01 | `integrate/swift-migration`（SOS 交付 + 解除志愿者注册死锁）|
| #3 | 08-06 | `integrate/swift-migration`（语音下单真机手测五轮缺陷修复）|
| #14 #15 #16 #17 | 08-09 | 各自特性分支 |
| #18 | 08-10 | `feat/voice-cross-turn-correction` |

**全部 `MERGEABLE`，没有冲突。** #2 / #3 的 head 就是工作线本身。做完的东西没落地，等于没做。

### B3 · 中 · 8 个 openspec 变更未归档，46 条任务未完成

`enable-independent-sos-safely` 与首页 SOS 条 delta 同一个能力的冲突，
`.claude/state.md` 2026-08-04 就记了，至今未决。

---

## C. 「列出来了但没有实际执行」

这一类高度集中，根因只有一个：**真机验证通道一直没打通。**

- **C1 · 真机端到端语音联调，一次都没做过。** handoff 原话：「上面全部走 Mock 与 stub，
  验的是状态机和文案，**不是识别质量**」。未勾条目：
  `enable-one-utterance-booking` 1B.7 / 5.5；
  `enable-cross-turn-voice-correction` 5.4 / 7.5 / 7.6 / 7.7；
  `disambiguate-same-name-start-place` 6.3（「第二个」这三个字能不能被 `SFSpeechRecognizer`
  稳定渲染成汉字，只有真人说了才知道）；
  `capture-order-end-location` 6.6（起终点会不会被抽反）；
  `capture-and-gate-runner-extra-needs` 5.6。
- **C2 · UI 测试本轮从未跑成。** `capture-order-end-location` 6.5 与
  `enable-independent-sos-safely` 8.8 都记着同一原因：设备走网络配对，runner bootstrap 时
  `Lost connection to testmanagerd`（记忆 `ui-test-runner-needs-usb-not-wifi` 里 code 74 的签名，插 USB 可解）。
- **C3 · SOS 云端链路在真实环境里一次都没端到端验过。** `enable-independent-sos-safely` 6.4：
  「触发真实 SOS 会给紧急联系人发真短信并惊动客服，不能拿测试账号随便打；需要与后端约定演练时间窗」。
  6.2a（后台/锁屏触发）、6.6（真机批跑）同样未做。
  **这是全 App 风险最高的路径，验证等级停在「编译通过 + Mock 绿」。**
- **C4 · `capture-and-gate-runner-extra-needs` 实质停摆。** 33 条任务里 22 条未完成，
  且卡在最前面：1.1「投 handoff 问自由文本需要一个接单后才下发的通道」——**这条投递本身就没做**。
  3.1~3.5 的实现全部未开始，`blindRun/Core/MockAPIClient.swift:1317` 的
  `mockVoiceSpecialNotes` 至今恒返 `nil`。
- **C5 · 生产水位线从未核实。** 见 §F.1。
- **C6 · 积分商城是硬编码占位。** `blindRun/Volunteer/VolunteerOrderFlowViews.swift:1713-1750`：
  积分显示 `Text("--")`，4 个商品写死在数组里，`VolunteerPointsViewModel` 只有一个 `errorMessage`
  和一个空的 `configure`，没有任何数据获取。入口在
  `blindRun/Volunteer/VolunteerHomeView.swift:1264`。文案「即将上线」是诚实的，列出只为清单完整。

---

## D. UI 与无障碍

**先说做到位的**（不然这份报告会给出错误印象）：盲人端遍历顺序与视觉顺序解耦、
地图 `accessibilityHidden(true)` + `allowsHitTesting(false)`
（`blindRun/BlindRunner/BlindOrderStatusView.swift:771-772`）、「重复当前状态」四个盲人页全覆盖、
Magic Tap 全屏 SOS、二次确认文案逐字锁定、主按钮用 `@ScaledMetric` 而非固定值 ——
这些都是对的，而且注释写清了为什么。

**贯穿三块空白的一件事**：它们精确落在同一个用户段 —— **低视力用户**，
而这个段在数据模型里是一等公民：`VisionLevel.lowVision = "LOW_VISION" / "低视力"`
（`blindRun/Core/Models/ProfileModels.swift:397/402`），还挂在订单上传给志愿者
（`blindRun/Core/Models/OrderModels.swift:329`）。

全盲用户走 VoiceOver 通道，那条做得很好。低视力用户走视觉通道，**那条从没被系统性验收过**。
代码自己也这么说 —— `blindRun/BlindRunner/BlindRunnerHomeView.swift:421-422`：
「这块面积对全盲用户没有点击收益 …… 它服务的是低视力用户和没开读屏的用户。」

**所以这不是三笔零散 UI 债，是一整条用户通道没人管。**

### D1 · 高 · `HighContrastText` 名不副实，且 `.status` 用的是四色里对比度最低的

`blindRun/Core/DesignSystem/HighContrastText.swift` 的 docstring 写
「高对比度文本组件，确保在深色/浅色模式下可读性」，实际只做两件事：
挑一个系统语义色 + **把** Dynamic Type **封顶**。没有任何对比度增强逻辑。

更要紧的是 `:30`：`.status` 这一档（订单状态文字，低视力用户最需要看清的那一行）
用的是 `AppColors.primary` = systemBlue，浅色模式对白底 **≈4.02:1**，低于 WCAG AA 正文的 4.5:1。

### D2 · 高 · 语义色当正文前景色用，三个明显不达标

浅色模式对 `systemBackground`（白）的对比度，按 WCAG 相对亮度公式算。
**处数只计可读文本（Text / Label），已剔除 `accessibilityHidden` 的装饰图标**：

| 色 | 值 | 对比度 | 文本处数 |
|---|---|---|---|
| `AppColors.warning` | systemOrange `#FF9500` | **≈2.20:1** | 9 |
| `AppColors.success` | systemGreen `#34C759` | **≈2.22:1** | 1 |
| `AppColors.destructive` | systemRed `#FF3B30` | **≈3.55:1** | 29 |
| `AppColors.primary` | systemBlue `#007AFF` | **≈4.02:1** | 3 + `HighContrastText.status` 全局 |

AA 正文要 4.5:1，大字（≥18pt bold）要 3:1。

`warning` 最差，而它标的恰好全是**阻断类提示**：

| 位置 | 文案 |
|---|---|
| `blindRun/BlindRunner/BlindBookingView.swift:1546` | 「需要开启定位权限才能创建预约。」 |
| `blindRun/BlindRunner/BlindBookingView.swift:1152` | `voiceWizard.fallbackMessage` —— 「语音下单服务暂时不可用」「连续两次没听到预约时间」 |
| `blindRun/BlindRunner/BlindOrderStatusView.swift:778` | 「同行位置暂时不可用」 |

第三条旁边的注释自己写着「盲人据此决定要不要打电话，**这是状态信息不是装饰**」，
然后用了全 App 对比度最低的颜色。

产品影响是**用户卡住且不知道为什么** —— 他看得见「开始约跑」按钮点了没反应，
看不见旁边那行解释；而这些都是一次性的、TTS 播完就过的信息，**视觉是唯一的持久通道**。
`destructive` 的 29 处 Text 是错误提示，同理。

**本 App 特有的放大因素**：陪跑是**户外**活动。阳光下屏幕有效对比度会进一步塌，
2.2:1 在室内勉强能认，在户外等于消失 —— 而户外正是使用场景。

**合规面**：无障碍类应用申请补贴、接政府 / 公益项目时通常要过 WCAG 2.1 AA 或 GB/T 37668，
2.2:1 是硬性不达标。

`blindRun/Core/DesignSystem/AppColors.swift` 一共只有 14 行，改动面很小；
深色模式本身没问题（系统色自带两套）。

### D3 · 中高 · Dynamic Type 被封顶在 accessibility3，没有理由说明

`blindRun/Core/DesignSystem/HighContrastText.swift:45`
`.dynamicTypeSize(...DynamicTypeSize.accessibility3)`。iOS 有 AX1~AX5 五档，这里砍掉最大两档 ——
而 AX4 / AX5 正是低视力用户实际会用的档位。

低视力用户里，**放大字体比读屏更常用** —— 很多人根本不开 VoiceOver，只把系统字号拉到最大。
体验是：在系统设置里调到最大，回到 App 发现字停在中间档不动了，
没有任何线索知道这是 App 主动限制的，只会归因成「这个 App 不支持大字」。

全仓**唯一**一处 `dynamicTypeSize` 就是这个封顶 —— 说明团队从没把「放大字」当成要支持的能力，
只当成要防的布局风险。而它写在名叫 `HighContrastText` 的组件里：
专门为可读性造的组件，是限制可读性的那一个。

### D4 · 中高 · 横屏与 iPad 声明了但从未适配

`blindRun.xcodeproj/project.pbxproj` 里 iPhone 与 iPad 都声明了
`UIInterfaceOrientationLandscapeLeft` / `LandscapeRight`。
而全仓 `horizontalSizeClass` / `verticalSizeClass` **0 命中**，没有任何 size class 分支或 iPad 专属布局。

- **iPhone 横屏**：可用高度约 390pt，`blindRun/BlindRunner/BlindRunnerHomeView.swift:414`
  的 `mapVisualHeight: CGFloat = 300` 是**固定值**、不随屏高变，底部还有 `safeAreaInset` 的 SOS 条
  → 「开始约跑」被推出首屏，必须滚动才找得到。
  全盲用户不受影响（遍历顺序与视觉解耦、双击任意位置激活），**只打低视力用户**
  —— 与 D1 / D3 叠加在同一群人身上。
- 谁会横屏：低视力用户常主动用横屏配合大字（一行能放下的字更多）；
  手机架在支架 / 轮椅上的；跑步时装臂带被系统转屏的。
- **iPad**：280pt 主按钮在 12.9" 上占比很小，反而不像主按钮；
  「地图铺满上半屏 + 巨大主按钮」的整个视觉层次在 iPad 上不成立。
  `AGENTS.md` 要求发布验证必须在 `iPad Pro (2)` 上跑，但没有一行 iPad 专属布局代码。

### D5 · 中 · `AccessibilityAuditTests` 只覆盖 2 个页面

`blindRunUITests/AccessibilityAuditTests.swift` 的 6 条用例全部打在
`BlindRunnerHome` 和 `BlindBooking` 上。

**`BlindOrderStatusView` 没有任何无障碍审计** —— 那是盲人整场陪跑期间停留的页面，
还带地图、SOS、拨号、取消订单、评价。
`BlindRunnerOnboardingView` / `BlindRunnerSettingsView` / `BlindIdentityVerificationView` /
`EmergencyContactsView` 同样 0 覆盖。

### D6 · 中 · 「跳过评价并返回首页」只有 52pt，低于本项目自己的 64pt 线

`blindRun/BlindRunner/BlindOrderStatusView.swift:732` `.frame(minHeight: 52)`。
skill `aidrun-a11y-voice` 写的是「盲人端关键主按钮高度 ≥ 64pt」。

同一屏的评分控件用 `.pickerStyle(.segmented)`（`:708`），segmented control 实际高约 32pt，
是这一页最难点中的控件。

> **2026-08-15 已修，并且比本条写的多五处。** 按这一条去改的时候顺手全仓扫了一遍
> `.frame(minHeight:)`，盲人侧低于 64pt 的**一共六处**，本条只点了其中一处：
> 「跳过评价并返回首页」52 →「临时显示身份证号」44 →
> 搜索地点 / 收藏这个出发地点 / 收藏地点行 三处 52。全部提到 64pt。
>
> 第六处「查看大图路线」44pt **不在本分支**：那个入口是历史订单那条线
> （`CompletedTrackSummaryView` 的全屏回放链接）带进来的，`main` 上还没有这段代码，
> 所以它跟着那个 PR 一起改，不在这里重复。
>
> 一处一处修正是这类缺陷会反复回来的原因，所以同时落了守卫
> `guard.mjs` 的 `small-touch-target`：盲人侧生产代码里 `.frame(minHeight: <64)` 一律拦，
> 志愿者端豁免（明眼人走 Apple 的 44pt 线），非触达目标行尾标注放行。
> 自测 `scripts/validate-guard.mjs` 49 → 54 条。
>
> 为什么之前没被 `AccessibilityAuditTests` 抓到：那条审计量的是**逐页点名的主按钮**
> （`minimumBlindPrimaryButtonHeight`），次级控件从来不在它的视野里。
>
> segmented 评分控件那半条**没动** —— 换控件会改评价交互本身，属另一件事。

### D7 · 中 · 13 处 `.font(.system(size:))` 固定字号，不随 Dynamic Type 缩放

最扎眼的是 `blindRun/Volunteer/VolunteerOrderFlowViews.swift:1729`（积分数字 48pt）、
`:1746`（图标 42pt）；另有 `blindRun/ContentView.swift:265/315`、
`blindRun/BlindRunner/BlindOrderStatusView.swift:623` 等。
志愿者端是明眼人，优先级低于盲人端，但低视力志愿者同样存在。

### D8 · 低 · `BlindRunnerSettingsView` 没有「重复当前状态」

它是设置列表，没有「当前状态」可复述，倾向于这是合理豁免。
列出来是因为规则字面写的是「每个关键盲人页面必须有」——
要么补，要么在 skill `aidrun-a11y-voice` 里写清豁免条件，别让下一个人重新纠结一遍。

---

## E. 已核实为「非问题」的存疑点

写在这里是为了防止下一轮重新调查一遍。

| 项 | 结论 |
|---|---|
| `/api/orders/voice` 未接 | spec `:956` 标了 `deprecated: true`，明确让改用 `POST /api/orders`。**前端做对了** |
| `/api/orders/available` 未接 | 公开订单池链路已删，派单走 WS `NEW_ORDER`；多处文档与 handoff 一致 |
| `/api/orders/{id}/status-logs`、`/reviews`(GET) | `docs/backend-open-questions-2026-07-31.md:86` 已关闭 |
| `/api/cs/**`、`/api/admin/**`（10 条） | 客服 / 管理端，不属于本 App |
| `ORDER_SELF_DISPATCH_FORBIDDEN` 未映射 | 后端 spec `:2268` 明说「当前一号一身份模型下不可触发，客户端可暂不做专用分支」 |
| 静默解码降级 | **生产路径干净**：20 处 `try? decode` 里 19 处在 `MockAPIClient` 且都有 `else` 分支，1 处是 `blindRun/Core/Models/ErrorModels.swift:197` 的信封兜底策略。`APIClient` 解码失败会记 `.decodingFailure` 诊断并抛 `APIError.decodingError` |
| `WSNewOrder` 不解 `specialNotes` | 有意为之，`blindRun/Core/Models/WebSocketModels.swift:191-206` 写清了理由，有回归用例钉住 |
| 环境切换器暴露给盲人 | `#if DEBUG` + `AppBuildChannel.allowsEnvironmentSwitcher` 双重门（`blindRun/BlindRunner/BlindRunnerSettingsView.swift:35-44`）|
| 未知 `eventType` 处理 | 一律不抑制、走通用分支播 `ttsText ?? body`（`blindRun/Core/AppRealtimeCoordinator.swift:786`），方向正确 |

---

## F. 仍然存疑、只读范围内无法定论

1. **生产水位线（最重要）** —— `47.114.113.171` 上 08-09 / 08-10 两批到底部署了没有。
   handoff 原话：「我们至今没核实过；没部署的话 `candidates` 恒为空数组，消歧轮走不到，
   **看起来会像前端没做**」。
   需要带 BLIND 角色的 JWT 探测；**无鉴权探测定不了论** ——
   真假路径同返 401 同信封（`docs/voice-booking-manual-test-20260805.md:98` 已实测）。
   安全做法是用 `docs/test-accounts.md` 的白名单账号走 `scripts/cloud-e2e.mjs`，
   **会真实发短信并创建订单，需先取得授权**。

2. **`/api/orders/voice/parse` 现在还 404 吗** —— 整个语音降级设计
   （`blindRun/Voice/VoiceOrderWizard.swift:168`、`:458`、`:739`、`parseIsUnavailable` 整条分支）
   和 A3 里 VoiceStatusQuery 不接后端 NLU 的理由，
   **全部建立在 2026-08-06 那一次观测上**，至今未复核。

3. **`candidates` 消歧轮在生产上走不走得到** —— 取决于 1。

---

## 后续动作

| 项 | 去向 |
|---|---|
| ~~A1 `blindPhone`~~ | **作废** —— 后端 `ca7c735` 已加齐，前端 `offersVolunteerCall` 与其窗口逐态一致 |
| A2 `addressShort` | 前端认领，下个变更接上（不需要后端做事） |
| A3 `classify-query` | 后端已合进 main（`4e31766`），可以开工 |
| A4 `keep-waiting` / `keep-rematching` | 已起草 openspec `offer-keep-waiting-before-auto-cancel`；**不拆 `.noVolunteer` 终态**（初稿那句是错的） |
| A5 / A6 | 需要产品判断，未立项 |
| B1 门禁读错文件 | **已修**（PR #16 + 补上它漏的第 5 道门禁）；`fetch` 那步仍靠人记 |
| D1–D4 低视力通道 | 建议整体验收立项，不要拆成零散修补 |

**建议再加一条机器守卫**（`AGENTS.md` §1.1）：手动跑那五个脚本时没有任何东西提醒「你读的是工作区
而且可能没 fetch」。钩子里已经有 `fetch`，脚本自己没有 —— 可以让脚本在读到工作区路径时打一行警告，
或干脆默认也走 `git show origin/main:`。本轮只记录，不实现。
