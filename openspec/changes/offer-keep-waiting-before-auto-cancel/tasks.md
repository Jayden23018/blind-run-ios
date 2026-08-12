# Tasks

## 1. 契约确认（可与实现并行，但结论到之前不锁分支行为）

- [ ] 1.1 投 handoff：`keep-waiting` 在 `api_spec.yaml:235-254` 只有 operationId 和 200，
      **没有 description**。前置状态 / 角色 / 上限目前只能靠 `keep-rematching` 的描述对称推断，
      请补齐。
- [ ] 1.2 同一条里问：收到 `NO_VOLUNTEER_AVAILABLE` 通知时订单状态是否**仍是**
      `PENDING_MATCH`/`REMATCHING`（通知文案说「仍在等待中」，而 `NO_VOLUNTEER` 是终态，
      两者同名不同义）。
- [ ] 1.3 同一条里问：延长成功后有没有 WebSocket 回告？只有 200 的话客户端只能播本地文案。
- [ ] 1.4 后端答复后回来更新 `proposal.md` / `design.md` / `specs/` **三份一起过**
      （记忆 `openspec-artifacts-drift-from-implementation`：同一变更里已经因此犯过三次）。

## 2. 状态判定

- [ ] 2.1 `RunOrderStatus.offersKeepWaiting`，写在 `blindRun/Core/Models/OrderDisplayHelpers.swift`，
      紧挨 `offersVolunteerCall`（同一套穷举 switch 写法，理由见 design D2）。
- [ ] 2.2 端点分派：`PENDING_MATCH` → `keep-waiting`，`REMATCHING` → `keep-rematching`。
      **`PUT` 不是 `POST`** —— 契约里两条都是 `put`。
- [ ] 2.3 不给 `.noVolunteer` 开口子（design D2 / proposal「必须先纠正的认识」）。

## 3. 订单状态页

- [ ] 3.1 `BlindOrderStatusView` 在 `offersKeepWaiting` 为真时渲染「继续等待」，
      高度 ≥64pt（skill `aidrun-a11y-voice`），带 `accessibilityLabel` / `accessibilityHint`。
- [ ] 3.2 **不加二次确认**（design D4）。取消订单那条的二次确认保持不动。
- [ ] 3.3 把该动作纳入「重复当前状态」的播报内容 —— 看不见屏幕的人靠它发现还能做什么。
- [ ] 3.4 成功文案用**进行时**、不含具体时长（design D6）。
- [ ] 3.5 409 `KEEP_WAITING_LIMIT_REACHED` → 播报上限已到 + 收起按钮（design D5）。
- [ ] 3.6 409 `ORDER_STATUS_NOT_ALLOWED` → 刷新订单详情，**不重试另一个端点**（design D3）。

## 4. Mock

- [ ] 4.1 `MockAPIClient` 支持两个端点，按当前 Mock 订单状态返 200 / 409。
- [ ] 4.2 Mock 里能造出「已达上限」这一档，否则 3.5 那条分支离线验不到。
      ⚠️ 别造后端不存在的成功回执形状 —— 契约只保证 `{"success": true}`。

## 5. 测试

- [ ] 5.1 先按符号定范围（`AGENTS.md` §11）：
      `offersKeepWaiting|keep-waiting|keep-rematching|KEEP_WAITING_LIMIT_REACHED`
- [ ] 5.2 单测：两个状态各自打到**正确**的端点；其余状态一个请求都不发。
- [ ] 5.3 单测：409 `ORDER_STATUS_NOT_ALLOWED` 后**没有**第二个请求发出（钉住 design D3）。
- [ ] 5.4 单测：`KEEP_WAITING_LIMIT_REACHED` 之后 `offersKeepWaiting` 对应的 UI 状态收起。
- [ ] 5.5 单测：成功文案不含数字时长（钉住 design D6，防止有人后来「优化」成「已延长 10 分钟」）。
- [ ] 5.6 UI 测试（Mock）：VoiceOver 下该按钮可达，且在「重复当前状态」里被念到。
      需 USB 连线（记忆 `ui-test-runner-needs-usb-not-wifi`）。
- [ ] 5.7 真机手测：`PENDING_MATCH` 订单上点一次，确认听到进行时反馈且订单没被取消。
- [ ] 5.8 `node scripts/validate-spec-coverage.mjs`（新增两条路径要能在契约里找到）
      + `openspec validate --all --strict --no-interactive`。
      ⚠️ 跑 spec-coverage 前先 `git -C ../demo fetch origin main` 再导出 `origin/main` 的契约
      （记忆 `prepush-contract-gate-reads-backend-worktree`：不 fetch 会拿到几小时前的快照）。

## 6. 收尾

- [ ] 6.1 1.x 的契约结论已落到后端，且 handoff 里那条已 `- [x]`。
- [ ] 6.2 5.x 全部真跑过且非零执行（`passed=0 failed=0` 一律当失败查）。
- [ ] 6.3 更新 `docs/05-page-specs.md` 的订单状态页小节。
- [ ] 6.4 **归档顺序**：本变更 MODIFY 的 `Blind runner state updates remain status driven`
      与 `enable-live-escort-location-and-track-summary` 是同一条，且本变更的 MODIFIED 块
      **已基于它那一版写**。必须**在它之后**归档，否则会把它的两个 Scenario 覆盖回去。
- [ ] 6.5 `openspec archive offer-keep-waiting-before-auto-cancel`。
