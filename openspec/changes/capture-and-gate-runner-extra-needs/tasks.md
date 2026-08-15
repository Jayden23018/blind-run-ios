# Tasks

> 顺序有依赖：第 1 组是**阻塞项**，第 3 组必须等它有结论。第 2 组与契约结论无关，可以先做。

## 0. 前置结论（已完成，不要重新推导）

- [x] 0.1 确认 `/api/orders/voice/parse` 响应已含 `specialNotes` / `hasGuideDog` / `pacePreference`
      —— 后端 `docs/api_spec.yaml:2835-2843`，客户端 DTO `blindRun/Core/Models/VoiceOrderModels.swift:113-122`。
- [x] 0.2 确认唯一缺口是 `VoiceOrderWizard.parseFreeform`（`blindRun/Voice/VoiceOrderWizard.swift:403`）
      没有回写这三个槽位；下单请求侧（`OrderModels.swift:320-324`）与订单详情展示侧均已就绪。
- [x] 0.3 确认存量泄露：`WSNewOrder.specialNotes`（`WebSocketModels.swift:204`，后端
      `docs/websocket-protocol.md:359,376`）→ 派单弹窗 `VolunteerHomeView.swift:1685`，
      紧邻倒计时 `:1694` 与接单/拒绝按钮 `:1700`，即**接单前**。违反 `AGENTS.md §8`。
- [x] 0.4 确认与 `enable-one-utterance-booking` 不 delta 同一能力：那个变更 delta
      `blind-runner-voice-first-experience`，本变更新增 `blind-runner-extra-needs`。
- [x] 0.5 确认语音向导现为两轮 `.freeform` → `.confirm`，逐项修改已于 2026-08-06 删除
      （`VoiceOrderWizard.swift:29-53`，`Command` 只剩 `confirm/restart/repeatBack/unrecognized`）。

## 1. 契约（阻塞第 3 组）

- [x] 1.1 投 handoff：自由文本额外需求需要一个「接单后才下发」的通道；路线 A（改 `specialNotes`
      下发时机）vs 路线 B（新增字段）请后端拍板。**已投**，见 `demo/docs/handoff.md` 待后端确认。
      核对于 2026-08-15：handoff `6062`（我方提问，`- [x]`）→ `2063` 后端答复。
      后端已把 `specialNotes` 从接单前的两条路径删掉（破坏性变更，2026-08-07）。
- [x] 1.2 同一条里问清：`specialNotes` 现在举例的「请在南门入口等候」这类**碰头点提示**要不要
      保留在接单前？要的话应拆成独立的结构化槽位，而不是让自由文本兼两职（见 `design.md` D3）。
      **已投并已互相答过**：handoff `2106-2110` 后端提 `meetingPointHint`，`2155-2172` 我方答复。
- [x] 1.3 同一条里问清：`maxLength: 200` 能否放宽？口语化的身体状况说明容易超（`design.md` D4）。
      **已投**：handoff `6111`；后端在 `2109` 表态「同理 200→500 一并等 `meetingPointHint` 那条回复」。
- [ ] 1.4 后端答复后，更新本变更的 `proposal.md` / `design.md` / `specs/` **三份一起过**
      —— 只改实现不改 spec 是本仓库已犯过三次的漂移（记忆 `openspec-artifacts-drift-from-implementation`）。

> ⚠️ **2026-08-15 对账后的真实阻塞点：卡的不是后端，是产品。**
>
> 1.1–1.3 三条早就投完、后端也回过了。真正悬着的是 handoff `2155-2172` 我方那条答复里
> 提给产品的两问：**① 语音路径要不要也承载 `meetingPointHint`？② 如果要，读回时那句
> 「这句话附近志愿者接单前就能听到」的告知措辞谁给？**
>
> 后端的前置条件是「输入界面必须在采集时就告诉用户接单前可见」。打字路径加一行提示就行；
> **语音路径没有输入框、没有可视标签**，履行同样的告知只能在读回时用 TTS 念出来，
> 而盲人端每多一句播报都是实打实的成本。这不是工程判断，只能产品定。
>
> 在此之前 3.2 保持不做：**不把任何自由文本写进接单前可见的字段**。
> 本变更名字里的 gate 就是这件事，不做 3.2 不等于没做完 —— 它是被设计成有条件的。

## 2. 存量泄露的展示端（不依赖契约结论）

- [x] 2.1 **派单弹窗**：`VolunteerHomeView.swift:1685` 那 6 行已删。
      但只删渲染不够 —— 字段还在类型上，下一个人加回去没有任何东西拦着。
      **根因修法是把 `specialNotes` 从 `WSNewOrder` 整个删掉**（`WebSocketModels.swift:189-221`）：
      后端照发，`JSONDecoder` 忽略多余键，那段文本从此进不了 App 的任何一个类型，编译器替我们守着。
- [x] 2.2 逐个核实其余展示面（**没照抄，自己读的**）：
      - `VolunteerServiceOrderEssentials`（`:2544`）→ 只被在服务中的底部面板 `:2399` 用 → **接单后，保留**
      - `VolunteerAvailableOrderCard`（`:2144`）→ 只渲染 `routeNotes`，不渲染 `specialNotes` → 屏幕上不漏
      - ⚠️ `VolunteerOrderInfoSection`（`:2780`）→ **这是第二处真实泄露**：
        「可接订单」列表 `:449-450` 直接 `NavigationLink` 到 `VolunteerOrderDetailView`，
        那一页 `:921` 渲染它，而列表里的订单是 `PENDING_MATCH` —— **任何志愿者都能点进去读**。
        比弹窗更糟：弹窗是依次 1~3 人看到，这里是可随时浏览的列表。
- [x] 2.3 判据集中到 `RunOrderStatus.disclosesBlindRunnerNotesToVolunteer`
      （`OrderDisplayHelpers.swift`），穷举 switch：
      `PENDING_MATCH` / `REMATCHING` / `NO_VOLUNTEER` / `.unknown` 关，其余开。
      不就地写 `!= .pendingMatch` 的两个理由都在那段注释里（`REMATCHING` 的原志愿者已退出；
      未知状态的保守方向是**关**，与这一族其他 helper 相反）。
- [x] 2.4 两条测试都已真跑（真机，`passed=320 failed=0`）：
      - `AppRealtimeCoordinatorTests.testNewOrderCarryingSpecialNotesDecodesButNeverReachesTheClient`
        —— 带 `specialNotes` 的载荷仍解得出来（否则派单静默失效），且 `Mirror` 遍历确认那段文本
        不在解出来的对象里。**已验红**：把字段加回 `WSNewOrder`，该用例立刻失败。
      - `OrderEnumLeniencyDecodingTests.testBlindRunnerNotesAreDisclosedOnlyAfterAVolunteerHasAccepted`
        —— 9 个状态逐个钉死，并断言两组之和 == `allCases.count`，新加状态必须回来归类。
- [x] 2.5 `routeNotes`（路线备注）**已一并收进同一条闸**（2026-08-07，后端拍板同口径并在适配）。
      原先留它的理由（用途看着无害、是接单前的决策依据）站不住：**风险跟字段类型走，不跟用途走** ——
      同一个输入框里写「我住院刚出来，只能走平路」完全自然，而客户端在展示前分不出用户写了哪一种。
      两处改动：
      - `VolunteerAvailableOrderCard`（`:2165`）直接不再渲染 —— 这张卡片按定义只在闸关着的一侧出现，
        写成 `if` 反而像留了可开的口子。核实过 `VolunteerAvailableOrderRow.accessibilityLabel`（`:28-31`）
        本来就不含备注，**读屏那条路没有单独的泄露**。
      - `VolunteerOrderInfoSection`（`:2802`）接上 `showsSensitiveNotes`，与特殊说明同闸。
      - `VolunteerServiceOrderEssentials` 不加闸（只被服务中面板用），已在类型上留注释说明前提。
- [x] 2.6 `GET /api/orders/available` 在契约里是裸 `type: object`（`api_spec.yaml:1899-1905`），
      返不返 `specialNotes` 无从判断 —— 客户端现在不渲染了，但数据可能仍到设备上。已投 handoff ⑥。
      **答（2026-08-07）：两个方向同时解掉，顾虑不再成立。**
      - 契约侧：后端已补 `components.schemas.AvailableOrderResponse`（`api_spec.yaml:3500`），
        9 个分量，**明确不含** `specialNotes` / `routeNotes` —— `AvailableOrderResponse.java`
        的 record 注释里写死了理由（「这里每个字段都会下发给还没接单、可能最终拒单的志愿者」）。
      - 客户端侧：那条链路整个删了。唯一的调用点是一个只在 `#Preview` 里构造、
        App 里根本进不去的页面，**现在 App 不再请求这条路径**。
        顺带查出它从 2026-05-24 起就把响应解错（裸数组解成 `PagedOrderResponse`）
        并被宽容解码器静默吞成空列表。见 PR #5。

## 3. iOS 实现（**等 1.1 有结论后再开始** —— 1.1 已于 2026-08-07 有结论，见第 1 节）

- [x] 3.1 `parseFreeform` 回写 `hasGuideDog` / `pacePreference` 到 `bookingViewModel`。
      **已做**（`VoiceOrderWizard.swift` 的 `apply`，「三个可选槽位」那段）。
      任务里那条 ⚠️ 的担心**不成立**：`hasGuideDogThisRun` 早已是三态 `Bool?`
      （`BlindBookingView.swift:208`），`makeCreateOrderRequest`（`:811`）原样透传，
      注释里逐条写了两个方向都不许压平的理由。核对于 2026-08-15。
- [x] 3.2 自由文本按 1.1 的结论落到对应字段；结论出来前不写入任何接单前可见的字段。
      **前置条件已满足**：后端 2026-08-07 走路线 A，`specialNotes` 已从接单前的两条下发路径删除
      （handoff `2063`），前端同期把 `routeNotes` 收进同一条闸。所以写 `specialNotes` 是符合设计的。
      本轮补上了**客户端自己的子串校验**（见 5.3）—— spec 的 `Parser returns rewritten text`
      场景一直没有实现，代码注释写的是「后端保证，所以直接落」，而那是一条我们没验过的声称。
- [x] 3.3 读回文案念出抽到的结构化槽位；未抽到的不念（`design.md` D5）。
      **已做**：`confirmPrompt` → `optionalNeedsSpeechSummary`（`BlindBookingView.swift:422`），
      空态返回「没有填写选填跑步需求」而不逐项报空。`false` 也念（`:407-415`）。
- [x] 3.4 超长处理：不静默丢（`design.md` D4）。
      **已做，但触发条件与原任务写的不同** —— 原任务假设「备注超过 200 要截断」，
      而契约里 `/parse` 响应的 `specialNotes` 本身就带 `maxLength: 200`，客户端没有可截断的东西。
      真正会发生的是**转录**超过 200 字：后端跳过大模型走纯正则，而终点没有正则实现、
      备注「只在触发大模型那次顺带抽」—— **两项一起消失且零报错**。
      实现：`ParseVoiceOrderRequest.modelFallbackCharacterLimit` +
      `VoiceOrderWizard.longUtteranceNotice(forCharacterCount:)`，在读回**之前**先说一句并给出路。
      `design.md` D4 与 spec 的对应场景已一并订正。
- [x] 3.5 `MockAPIClient.mockVoiceSpecialNotes` —— 此前恒返 `nil`，语音链路在 Mock 里
      根本走不到自由文本分支。**已补**：按原话取子串，且复现超字数线后的降级（超线即 nil），
      与生产共用 `modelFallbackCharacterLimit` 常量。

## 4. 文档

- [x] 4.1 `docs/05-page-specs.md`：派单弹窗字段清单标注哪些接单前可见、哪些接单后可见。
      **已改，而且它原来是错的** —— `:671` 把「路线备注」「特殊说明」列在接单前可见里，
      正是这个变更要修的泄露。照着它改的人会把闸重新打开。
- [x] 4.2 `docs/09-accessibility-and-voice-guidelines.md`：读回必播报节点补额外需求。
      **已加两条**：额外需求「抽到才念、`false` 也念、备注念原文、空态不念」；说得太长的提示。
- [x] 4.3 `AGENTS.md §8` 那条「接单前隐藏敏感信息」补一句可执行的判据（取值空间封不封闭），
      现在它只是原则，判不了具体字段。**已补**，并写明实现闸的位置。

## 5. 测试（按 `AGENTS.md §11` 只跑覆盖面，不裸跑全量）

- [x] 5.1 先按符号定范围：`specialNotes|hasGuideDog|pacePreference|parseFreeform|WSNewOrder`
      搜 `blindRunTests/`，只跑命中的 suite。
      命中：`VoiceOrderWizardTests`(20) / `EscortNeedsTests`(10) / `blindRunTests`(22) 等 12 个文件。
- [x] 5.2 单测：`hasGuideDog == nil` 时下单请求不含 `hasGuideDogThisRun`；`== false` 时含且为 `false`。
      `RunnerExtraNeedsVoiceTests` 前三条。
- [x] 5.3 单测：解析返回的自由文本不是 transcript 子串时被丢弃，且订单照常创建。
      `testRewrittenNotesAreDiscardedAndTheBookingStillProceeds`。
      配套 `testNotesInheritedFromAnEarlierRoundSurviveACorrectionRound` 钉住反向陷阱：
      跨轮修正时后端会把上一轮备注从 `current` 继承回来，只比对本轮 transcript
      会把用户真说过的备注当伪造删掉。
- [x] 5.4 单测：读回文案在抽到导盲犬/配速时念出、未抽到时不念空态。
      `testReadbackSpeaksEveryCapturedOptionalNeed` / `...SpeaksAnExplicitNoGuideDog` /
      `...DoesNotEnumerateEmptyOptionalNeeds`。
- [ ] 5.5 UI 测试（Mock）：派单弹窗不出现自由文本（需 USB 连线，见记忆 `ui-test-runner-needs-usb-not-wifi`）。
- [ ] 5.6 真机手测（开 VoiceOver）：说一句带身体状况的整话，确认读回念得出原话、
      确认后志愿者端接单前看不到、接单后看得到。**只能人耳验**。
- [ ] 5.7 `node scripts/validate-spec-coverage.mjs` + `openspec validate --all --strict --no-interactive`。

## 6. 验收

- [ ] 6.1 契约结论已落到后端 `api_spec.yaml` / `websocket-protocol.md`，且 handoff 里那条已 `- [x]`。
- [ ] 6.2 上面 5.x 全部真跑过且非零执行（`passed=0 failed=0` 一律当失败查）。
- [ ] 6.3 `openspec archive capture-and-gate-runner-extra-needs`。
