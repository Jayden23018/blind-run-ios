## Why

盲人端「隐私与授权」现在一页摊开三项同意，每项都有说明、状态和一个撤回按钮。整页很长，三个撤回按钮挨在一起，误触撤回的机会多。负责人 2026-11-05 批准照设置 App「隐私与安全」拆成两层（Jayden23018/blind-run-ios#754，原话「按推荐开工」）。

## What Changes

- 第一层改成：顶部说明卡（盾牌图标、标题、一句话），下面一组三行。每行是图标、名称、灰字「已同意 / 没有同意」、箭头。组下一句说明。第一层不再有撤回按钮。
- 新增第二层：每项一页。依次是「当前」状态行、用途卡、红字撤回行「撤回 xx 的同意」、组下说明。
- 撤回的五种结果（成功、陪跑中被拦、失败、资料未加载、撤回待保存）全部保留。结果显示在撤回行下面，同时朗读。
- 撤回按钮的 `privacyRevoke*` 标识挂到第二层的撤回行上；UI 用例多点一层。
- 陪跑员端「隐私与授权」不变。

## Capabilities

### New Capabilities

（无）

### Modified Capabilities

- `privacy-authorization-hub`：「三项同意在一处撤回」改成两层：列表看状态，进详情页撤回。

## Impact

- `blindRun/Profile/PrivacyAuthorizationView.swift`（第一层）、新增 `blindRun/Profile/PrivacyConsentDetailView.swift`（第二层）、`blindRun/Profile/PrivacyConsentRow.swift`（加列表行与撤回行的组件，陪跑员端用的 `PrivacyConsentRow` 不动）。
- UI 用例：`blindRunUITests/PrivacyAuthorizationUITests.swift`、`blindRunUITests/AccessibilityAuditTests+PrivacyAuthorization.swift`。
- 不改接口、不改同意记录、不改撤回逻辑。不改 `ProfileModule.swift`（视力那项仍调它的 `withdrawVisionConsent()`）。
