## 1. 撤回入口

- [x] 1.1 `AppState` 加语音同意撤回与盲人位置同意撤回（陪跑中拒绝），撤回位置同意后重算定位意图并通知同行协调器
- [x] 1.2 新页面「隐私与授权」，三项同一交互；视力那项复用资料页 view model
- [x] 1.3 盲人端设置页加入口

- [x] 1.4 陪跑员端（#530）：设置入口、同一版式（`PrivacyConsentRow`）、撤回时关接单开关、陪跑中拒绝

## 2. 验证

- [x] 2.1 单测：撤回语音同意后 `/parse` 请求计数不变；撤回位置同意停定位、求助不附位置；陪跑中拒绝撤回
- [x] 2.2 UI 用例：撤回按钮 ≥ 64pt、读屏标签
- [x] 2.3 编译门禁、SwiftLint 棘轮、`openspec validate --strict`
- [x] 2.5 单测：陪跑员撤回时关开关并同步服务端、开关关着只撤回、陪跑中拒绝
- [x] 2.6 陪跑员端真机（iPhone 16 Pro 有线，2026-10-28/29）：`VolunteerPrivacyAuthorizationTests` `PrivacyAuthorizationTests` 全过；整页审计四种外观（含撤回按钮 ≥ 64pt）`passed=2 failed=0`、0 条 `[AUDIT]`；验红（撤回时不等服务端关接单开关）预期的 2 条红
- [x] 2.4 真机跑覆盖 suite 与无障碍审计，`passed=N failed=0`，做一次验红（iPhone 16 Pro 有线，2026-10-28/29）：覆盖 suite 与两条 64pt UI 用例 `passed=65`（唯一失败是审计用例二次启动撞设备侧错误）；整页审计四种外观重跑 `passed=2 failed=0`、0 条 `[AUDIT]`；验红预期的 3 条红
