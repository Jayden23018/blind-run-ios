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

- [ ] 1.1 投 handoff：自由文本额外需求需要一个「接单后才下发」的通道；路线 A（改 `specialNotes`
      下发时机）vs 路线 B（新增字段）请后端拍板。**已投**，见 `demo/docs/handoff.md` 待后端确认。
- [ ] 1.2 同一条里问清：`specialNotes` 现在举例的「请在南门入口等候」这类**碰头点提示**要不要
      保留在接单前？要的话应拆成独立的结构化槽位，而不是让自由文本兼两职（见 `design.md` D3）。
- [ ] 1.3 同一条里问清：`maxLength: 200` 能否放宽？口语化的身体状况说明容易超（`design.md` D4）。
- [ ] 1.4 后端答复后，更新本变更的 `proposal.md` / `design.md` / `specs/` **三份一起过**
      —— 只改实现不改 spec 是本仓库已犯过三次的漂移（记忆 `openspec-artifacts-drift-from-implementation`）。

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
- [ ] 2.5 `routeNotes`（路线备注）同为自由文本、同在接单前可见（`:2165` / `:2794`），
      按 `design.md` D2 的判据本该也归到接单后。**本轮不改**：它只有表单入口、语音不写它，
      量级不同，且它的产品用途（「沿湖边跑道」这类）恰恰是志愿者接单前的决策依据。
      已随 handoff ⑥ 一并问后端。要在 §4 文档里写明这是**已知的、有意留下的**边界。
- [ ] 2.6 `GET /api/orders/available` 在契约里是裸 `type: object`（`api_spec.yaml:1899-1905`），
      返不返 `specialNotes` 无从判断 —— 客户端现在不渲染了，但数据可能仍到设备上。已投 handoff ⑥。

## 3. iOS 实现（**等 1.1 有结论后再开始**）

- [ ] 3.1 `parseFreeform` 回写 `hasGuideDog` / `pacePreference` 到 `bookingViewModel`。
      ⚠️ `hasGuideDog == nil` 时**不要**写 `false`：`BlindBookingViewModel.hasGuideDogThisRun` 是
      非可选 `Bool`（`BlindBookingView.swift:185`），`makeCreateOrderRequest` 靠
      `hasGuideDogThisRun ? true : nil`（`:691`）把 `false` 转回不传 —— 先确认这条转换在
      「本次明确不带」的场景下是否已经丢了语义，是的话本任务要一并修。
- [ ] 3.2 自由文本按 1.1 的结论落到对应字段；结论出来前不写入任何接单前可见的字段。
- [ ] 3.3 读回文案念出抽到的结构化槽位；未抽到的不念（`design.md` D5）。
- [ ] 3.4 超长处理：读回明确说出「记不下的部分」，不静默截断（`design.md` D4）。
- [ ] 3.5 `MockAPIClient.mockVoiceSpecialNotes` —— 目前 `:1317` 恒返 `nil`，语音链路在 Mock 里
      根本走不到自由文本分支。补上按原话取子串的实现（**必须是子串**，Mock 编一句出来会让
      「原文照录」这条规格在开发期永远验不到）。

## 4. 文档

- [ ] 4.1 `docs/05-page-specs.md`：派单弹窗字段清单标注哪些接单前可见、哪些接单后可见。
- [ ] 4.2 `docs/09-accessibility-and-voice-guidelines.md`：读回必播报节点补额外需求。
- [ ] 4.3 `AGENTS.md §8` 那条「接单前隐藏敏感信息」补一句可执行的判据（取值空间封不封闭），
      现在它只是原则，判不了具体字段。

## 5. 测试（按 `AGENTS.md §11` 只跑覆盖面，不裸跑全量）

- [ ] 5.1 先按符号定范围：`specialNotes|hasGuideDog|pacePreference|parseFreeform|WSNewOrder`
      搜 `blindRunTests/`，只跑命中的 suite。
- [ ] 5.2 单测：`hasGuideDog == nil` 时下单请求不含 `hasGuideDogThisRun`；`== false` 时含且为 `false`。
- [ ] 5.3 单测：解析返回的自由文本不是 transcript 子串时被丢弃，且订单照常创建。
- [ ] 5.4 单测：读回文案在抽到导盲犬/配速时念出、未抽到时不念空态。
- [ ] 5.5 UI 测试（Mock）：派单弹窗不出现自由文本（需 USB 连线，见记忆 `ui-test-runner-needs-usb-not-wifi`）。
- [ ] 5.6 真机手测（开 VoiceOver）：说一句带身体状况的整话，确认读回念得出原话、
      确认后志愿者端接单前看不到、接单后看得到。**只能人耳验**。
- [ ] 5.7 `node scripts/validate-spec-coverage.mjs` + `openspec validate --all --strict --no-interactive`。

## 6. 验收

- [ ] 6.1 契约结论已落到后端 `api_spec.yaml` / `websocket-protocol.md`，且 handoff 里那条已 `- [x]`。
- [ ] 6.2 上面 5.x 全部真跑过且非零执行（`passed=0 failed=0` 一律当失败查）。
- [ ] 6.3 `openspec archive capture-and-gate-runner-extra-needs`。
