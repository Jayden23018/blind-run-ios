# Tasks

- [x] 1.1 `CancelOrderResponse` 模型；`OrderServing.cancel` 返回它（`@discardableResult`），Mock 与 `FakeOrderService` 同步。
- [x] 1.2 `VolunteerCancelAnnouncement`：纯值类型，处理「先念取消句 / 后到响应」与反过来两种顺序。
- [x] 1.3 陪跑员订单页、跑步中页、首页「我去不了」三条取消路径接上；`REMATCHING` 时只念一句。
- [x] 1.4 `RuleParamsResponse` + `RuleParams`（含回退与合法性校验）；`AuthServing.ruleParams()`；`AppState.loadRuleParamsIfNeeded()`。
- [x] 1.5 取消弹层窗口与自动打开提前量改读 `AppState.ruleParams`；弹层窗口内那段恢复「会记一次临时取消」。
- [x] 1.6 Mock `/api/config/rules`；漂移探测器 filter 加 `/api/config/rules` 并重新生成。
- [ ] 2.1 单测：响应解码、两种顺序的播报、只念一句、规则回退与非法值、弹层按下发窗口判；验红。
- [ ] 2.2 `openspec validate --all --strict`；`build-for-testing`；真机跑覆盖的 suite。

> 2026-10-06：1.x 已实现，`build-for-testing` TEST BUILD SUCCEEDED，`openspec validate --all --strict` 通过。
> **真机测试没跑**：iPhone 与 iPad 当晚都锁屏 / 不可用，验红也没做，所以 2.1 / 2.2 不勾，PR 保持草稿。
> 实现时顺带修了同一条路径上的两处：转 `REMATCHING` 时先念盲人端状态句、再被同档取消句切断；
> 取消那一句「系统将为盲人重新匹配」在重匹到上限（直接 `CANCELLED`）时不成立，改为「这一单不在你名下了」。
> 陪跑员页状态播报整张表借用盲人端文案的根因见 iOS #333，不在本变更内。
