## Context

`VolunteerRegistrationViewModel.currentStep` 只有两个值（`.basicInfo`、`.faceVerify`），由后端注册状态决定。第 1 步的六个字段在一次 `submitBasicInfo()` 里提交；提交按钮先过 `handleBasicInfoSubmitTapped()` 的单独同意闸（PIPL 第 29 条）。拒绝人脸的接口 `declineFaceVerify()` 要求二要素已经 APPROVED，否则后端返回 400 并回退到第 1 步。

## Goals / Non-Goals

**Goals:**
- 说明页 + 身份、经历、刷脸三屏，一屏一件事，按钮固定在屏幕底部。
- 接口与提交时机的语义不变：一次请求提交六个字段，提交前过同意闸。
- 说明页给出改走人工审核的入口，复用现有拒绝人脸路径。

**Non-Goals:**
- 不改同意层、活体认证、轮询、结束页（`VolunteerReadinessProgressContent` 与替代路径落地屏）。
- 不改接口、不改 `AppColors.swift`。
- 不改刷脸页上已有的「不同意人脸认证，改用其他方式」整行按钮（监管要求同屏、同尺寸）。

## Decisions

1. **子页状态放在 ViewModel**：新增 `basicInfoPage`（`.intro` / `.identity` / `.experience`），只在 `currentStep == .basicInfo` 时有意义。放 ViewModel 而不是 `@State`，单测能直接验「下一步」「跳过」「上一步」的走向。后端把人带回 `.basicInfo` 的两条路（`returnToBasicInfoForIdentityEdit`、拒绝失败的 400）直接落到 `.identity`，不再显示说明页。
2. **「下一步」可点的判据**：第 1 步用新的 `identityPageMissingFields`（列出还差的字段名），为空才可点；第 2 步无必填，提交仍走原来的 `canSubmitBasicInfo`。原来的 `basicInfoValidationMessage` 不动，`submitBasicInfo()` 照旧用它兜底。
3. **「跳过」不清空已填内容**：跳过只表示「不再填」，点跳过和点下一步走同一个提交入口 `handleBasicInfoSubmitTapped()`。清空会让回头看的人发现刚填的字没了。
4. **替代路径的接法**：说明页第二个按钮把 `prefersAlternativeIdentityPath` 设为 true 并进入第 1 步。提交成功、状态落到 `.faceVerify` 时，`syncStatusAfterBasicInfoSuccess` 不播「身份核验通过，请开始活体认证」，改为直接 `await declineFaceVerify()`。理由：拒绝接口要求二要素先通过，说明页那一刻还调不了；而用户已经明确选过一次，再让他在刷脸页点第二次是多一步。刷脸页上原有的拒绝按钮与替代路径落地屏上的「改用人脸认证」都保留，可以随时改主意。
5. **导航栏**：第 1 步保留系统返回键（离开注册）；第 2 步隐藏系统返回键，页内左上「上一步」，右上「跳过」。iOS 27 会把工具栏文字按钮包成玻璃胶囊，审计报对比度与字号（记忆 `sheet-toolbar-text-button-fails-audit`），所以「上一步」「跳过」做成页内按钮行，不放 `.toolbar`。
6. **固定底栏**：`VStack { ScrollView; 底栏 }`，滚动区在底栏上沿结束，内容不会滚到底栏后面，不需要接进审计的 `occludingBarTop`。
7. **刷脸页说明文字**：定稿写「刷脸前会先请你同意使用身份证号和人脸信息」，但同意层实际在第 2 步「下一步」时弹出（提交前），到刷脸页时已经同意过。照实写：第 2 步按钮下写「点下一步会先请你同意使用身份证号和人脸信息，再一起提交第 1、2 步」，刷脸页按钮下写「点开始后会打开刷脸页面」。

## Risks / Trade-offs

- [第 2 步提交失败时字段不在同一屏] → 错误照原样显示在第 2 步按钮上方；身份类错误由后端回退到第 1 步时会自动跳回 `.identity`。
- [自动调拒绝接口] → 只在用户点过说明页第二个按钮、且提交后状态是 `.faceVerify` 时发生；失败分支复用 `handleDeclineFailure`。
- [AX5 下底栏变高] → 底栏只放按钮和一行说明，滚动区仍可滚；审计用例覆盖 AX5。
