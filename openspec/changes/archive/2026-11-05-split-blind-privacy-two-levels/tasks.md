## 1. 页面

- [x] 1.1 `PrivacyConsentRow.swift` 加第一层列表行和第二层撤回行、结果行组件（陪跑员端 `PrivacyConsentRow` 不动）
- [x] 1.2 `PrivacyAuthorizationView` 改成第一层：说明卡 + 三行 + 组下说明，返回时刷新状态
- [x] 1.3 新增 `PrivacyConsentDetailView.swift`：语音、视力、位置三个详情页，五种撤回结果显示在撤回行下面并朗读
- [x] 1.4 `privacyRevoke*` 标识挂到第二层撤回行；第一层三行加新标识

## 2. 用例

- [x] 2.1 `PrivacyAuthorizationUITests` 多点一层进详情页再断言撤回行
- [x] 2.2 `AccessibilityAuditTests+PrivacyAuthorization` 盲人端审计改成审第一层和每个详情页

## 3. 收尾

- [x] 3.1 build-for-testing 编译通过（负责人 2026-11-05 定：不跑测试）
- [x] 3.2 定稿图入 `docs/ui/mockups/blind-privacy-20261105/`，INDEX 加一行
