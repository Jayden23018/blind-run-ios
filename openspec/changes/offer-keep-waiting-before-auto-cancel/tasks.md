# Tasks

## 1. 契约确认（可与实现并行，但结论到之前不锁分支行为）

- [x] 1.1 投 handoff：`keep-waiting` 在 `api_spec.yaml:235-254` 只有 operationId 和 200，
      **没有 description**。前置状态 / 角色 / 上限目前只能靠 `keep-rematching` 的描述对称推断，
      请补齐。
      —— 已投「待后端确认」（2026-08-12）。核 `origin/main` 后确认该缺口**仍然存在**，
      并补了一条契约两边都漏的：403 抛的是 `NOT_ORDER_PARTICIPANT`
      （`OrderLifecycleService.java:341`），不是 `ORDER_PERMISSION_DENIED`。
- [x] 1.2 同一条里问：收到 `NO_VOLUNTEER_AVAILABLE` 通知时订单状态是否**仍是**
      `PENDING_MATCH`/`REMATCHING`（通知文案说「仍在等待中」，而 `NO_VOLUNTEER` 是终态，
      两者同名不同义）。—— 已投，单独成条。
- [x] 1.3 同一条里问：延长成功后有没有 WebSocket 回告？只有 200 的话客户端只能播本地文案。
      —— 已投，单独成条，并写明「没有的话不需要你们加」。
- [x] 1.4 后端答复后回来更新 `proposal.md` / `design.md` / `specs/` **三份一起过**
      （记忆 `openspec-artifacts-drift-from-implementation`：同一变更里已经因此犯过三次）。
      —— **本轮无答复，三份 artifact 也无需改**：实现与已拍板的 D1–D7 逐条一致，
      四个问题都不改变客户端行为（详见 1.5）。后端回复后仍须回来走这一条。
- [x] 1.5 **本轮新发现，已投 handoff**：`keep-rematching` 的契约（`api_spec.yaml:265`/`:293`）
      写了一个实现里**根本不存在**的上限 —— `OrderLifecycleService.keepRematching:369-387`
      一个计数守卫都没有，注释还明写「ponytail: 不设上限」。于是那条端点上的
      `KEEP_WAITING_LIMIT_REACHED` 永不抛出。
      **不阻塞本变更**：客户端两个端点共用同一条错误分支，两种口径下行为都正确。
      已请后端拍板是删文档还是补实现。

## 2. 状态判定

- [x] 2.1 `RunOrderStatus.offersKeepWaiting`，写在 `blindRun/Core/Models/OrderDisplayHelpers.swift`，
      紧挨 `offersVolunteerCall`（同一套穷举 switch 写法，理由见 design D2）。
- [x] 2.2 端点分派：`PENDING_MATCH` → `keep-waiting`，`REMATCHING` → `keep-rematching`。
      **`PUT` 不是 `POST`** —— 契约里两条都是 `put`。
      ⚠️ **实现与 design 的一处偏差（结论不变，形状变了）**：原计划返回路径**后缀**字符串再在
      调用点插值，实测被 `scripts/validate-spec-coverage.mjs` 判为硬错误 ——
      两段插值都会归一成 `{param}`，得到契约里不存在的 `/api/orders/{param}/{param}`，
      这两个端点对契约门禁**彻底隐形**。改成小枚举 `KeepWaitingEndpoint`，
      完整路径在它内部写成字面量（注释里也不能出现示例路径，同样会被扫到）。
      判定仍是**一个**按状态穷举的 switch，没有第二处可漂移。
- [x] 2.3 不给 `.noVolunteer` 开口子（design D2 / proposal「必须先纠正的认识」）。

## 3. 订单状态页

- [x] 3.1 `BlindOrderStatusView` 在 `offersKeepWaiting` 为真时渲染「继续等待」，
      高度 ≥64pt（skill `aidrun-a11y-voice`），带 `accessibilityLabel` / `accessibilityHint`。
      —— 放在 `volunteerCallSection` 之后的同一个主动作版位（两者状态集互斥），
      共用 `primaryActionButtonHeight`（`@ScaledMetric` 140，随 Dynamic Type 缩放）。
- [x] 3.2 **不加二次确认**（design D4）。取消订单那条的二次确认保持不动。
- [x] 3.3 把该动作纳入「重复当前状态」的播报内容 —— 看不见屏幕的人靠它发现还能做什么。
- [x] 3.4 成功文案用**进行时**、不含具体时长（design D6）。
- [x] 3.5 409 `KEEP_WAITING_LIMIT_REACHED` → 播报上限已到 + 收起按钮（design D5）。
      上限标记按**单**记，换单时清空。
- [x] 3.6 409 `ORDER_STATUS_NOT_ALLOWED` → 刷新订单详情，**不重试另一个端点**（design D3）。

## 4. Mock

- [x] 4.1 `MockAPIClient` 支持两个端点，按当前 Mock 订单状态返 200 / 409。
      端点要求的状态由调用方传入，Mock **不猜**当前订单是什么 —— 猜的话就把
      「客户端打错了端点」这类 bug 遮掉了。
- [x] 4.2 Mock 里能造出「已达上限」这一档（`mockKeepWaitingLimit = 2`，刻意不用后端默认的 10，
      点 10 次没人会点）。成功回执严格是 `{"success": true}`，没有编造字段。

## 5. 测试

- [x] 5.1 先按符号定范围（`AGENTS.md` §11）：命中 `blindRunTests.swift`(11)、
      `OrderEnumLeniencyDecodingTests`(3)、`VoiceStatusQueryTests`(1)，
      加上改了 `MockAPIClient` 而纳入的 `MockAPIClientErrorCodeTests`，
      以及新建的 `KeepWaitingTests`。**未跑全量**：本次没有改动全 App 唯一出口 /
      共享单例 / 全局配置。
- [x] 5.2 单测：两个状态各自打到**正确**的端点；其余状态一个请求都不发。
- [x] 5.3 单测：409 `ORDER_STATUS_NOT_ALLOWED` 后**没有**第二个请求发出（钉住 design D3）。
- [x] 5.4 单测：`KEEP_WAITING_LIMIT_REACHED` 之后 `offersKeepWaiting` 对应的 UI 状态收起。
- [x] 5.5 单测：成功文案不含数字时长（钉住 design D6，防止有人后来「优化」成「已延长 10 分钟」）。
- [ ] 5.6 UI 测试（Mock）：VoiceOver 下该按钮可达，且在「重复当前状态」里被念到。
      需 USB 连线（记忆 `ui-test-runner-needs-usb-not-wifi`）。
      🔴 **已写完并编译通过，但一次都没执行过。**
      `AccessibilityAuditTests.testBlindOrderStatusOffersKeepWaitingWhileWaitingForAMatch`。
      真机 UI runner 起不来：`code 74 ... before establishing connection`，
      清掉残留 `DTServiceHub` 后重试仍失败。**已用对照组确认是环境不是代码** ——
      未经改动的既有用例 `testBlindHomeWithAnActiveOrderOffersAskQuestion` 报**同一个签名**。
      按记忆 `ui-test-runner-needs-usb-not-wifi`，这是 Wi-Fi 调试下 DTX 握手失败，
      需插 USB 重跑。**插上线后必须补跑本条。**
      （播报那半 UI 测试本来也测不到 —— 黑盒读不到 TTS 文本，由 5.3 那组单测的
      `testRepeatStatusMentionsKeepWaitingWhileWaiting` 承担。）
- [ ] 5.7 真机手测：`PENDING_MATCH` 订单上点一次，确认听到进行时反馈且订单没被取消。
      🔴 **未做，需人工。** 模拟器通道永久不可用（高德无 arm64-sim slice），
      真机 UI 自动化又因 5.6 那条起不来，这一条只能人手在设备上点。
- [x] 5.8 `node scripts/validate-spec-coverage.mjs`（新增两条路径要能在契约里找到）
      + `openspec validate --all --strict --no-interactive`。
      ⚠️ 跑 spec-coverage 前先 `git -C ../demo fetch origin main` 再导出 `origin/main` 的契约
      （记忆 `prepush-contract-gate-reads-backend-worktree`：不 fetch 会拿到几小时前的快照）。
      —— 已按此做（导出到 `/tmp/aidrun_spec.yaml` 再传入）。
      spec-coverage **第一次跑是红的**，就是它逼出了 2.2 那个改动；改完通过，
      前端调用路径数 44 → 45，两条端点已被计入。
      另跑了 `validate-docs` / `validate-guard`（28 条守卫自测）/ `validate-error-codes`，均通过。

## 6. 收尾

- [x] 6.1 1.x 的契约结论已落到后端，且 handoff 里那条已 `- [x]`。
      —— 后端 2026-08-09 那条「你们会做这个按钮吗」已打勾并逐条答复（含两个可选字段的取舍）；
      本轮新产生的 4 条已追加到「待后端确认」。
- [ ] 6.2 5.x 全部真跑过且非零执行（`passed=0 failed=0` 一律当失败查）。
      🔴 **单测部分达成，UI 部分没有。**
      单测：`passed=344 failed=0`（含 `KeepWaitingTests` 15 条，逐条从 result bundle 核过名字，
      不是数日志）。**并且验过红** —— 分别破坏 D3 / D5 / D6 三条不变式后重跑，
      对应 5 条用例以预期报错失败，证明这些断言真的会咬。
      UI：5.6 / 5.7 未执行，理由见上，**不得据此宣称已验证**。
- [x] 6.3 更新 `docs/05-page-specs.md` 的订单状态页小节。
- [ ] 6.4 **归档顺序**：本变更 MODIFY 的 `Blind runner state updates remain status driven`
      与 `enable-live-escort-location-and-track-summary` 是同一条，且本变更的 MODIFIED 块
      **已基于它那一版写**。必须**在它之后**归档，否则会把它的两个 Scenario 覆盖回去。
      —— **前置未满足：`enable-live-escort-location-and-track-summary` 仍未归档**
      （尚有 1 项未完成）。本变更**保持不归档**。
- [ ] 6.5 `openspec archive offer-keep-waiting-before-auto-cancel`。
      —— 被 6.4 阻塞，不执行。
