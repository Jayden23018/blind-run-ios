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

- [ ] 2.1 **P0 判定**：`VolunteerHomeView.swift:1685` 那 6 行是否本轮就删。删除是纯减法、不依赖后端，
      且今天表单里手打的「特殊说明」已经在漏。**未决 —— 需要项目负责人拍板本轮做还是随第 3 组一起做。**
- [ ] 2.2 若删：同时确认没有别的接单前展示面漏同一个字段
      （已知面：`VolunteerHomeView` 派单弹窗、`VolunteerOrderFlowViews.swift:2557-2565` / `:2794-2811`
      —— 后两处需逐个核实是接单前还是接单后视图，**不要照抄本文件的判断，自己读**）。
- [ ] 2.3 若删：加一条守卫或测试钉住它，别只改代码（`AGENTS.md §1`）。倾向测试：
      构造一条带 `specialNotes` 的 `WSNewOrder`，断言派单弹窗的可访问性树里不出现那段文本。

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
