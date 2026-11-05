## Context

`VolunteerSettingsView` 住在 `VolunteerOrderFlowViews.swift`（3500 行，已超 SwiftLint 基线），是一张 `List`。#707 已为个人资料 / 积分 / 证书三页做了一套分组卡片部件（`VolunteerAccountPagesStyle.swift`）。

## Goals / Non-Goals

- Goals：照定稿重排；入口与标识不丢；大字号可用；白字对比度达标。
- Non-Goals：不改任何子页；不改盲人端「我的」与两端共用的 `AccountSafetySettingsRows`；不画后端没有的数据（工单未读数、通知「已开启」以外的状态）。

## Decisions

1. **`ScrollView` + 分组卡，不用 `List`**：方块网格放进 `List` 行里，行内多个 `NavigationLink` 会互相抢点击。与 #707 三页同一套部件，看起来是一家。
2. **账户页用 push，不用 sheet**：定稿右上「完成」是健康 App 的 sheet 写法；但退出 / 删除账户的进度遮罩挂在根视图上，sheet 会盖在遮罩上面，遮罩期间背景不退出无障碍树（`blindRunUITests` 已有用例守着）。所以 push，标签栏在账户页隐藏。
3. **「联系客服与工单」「使用帮助与关于」保留成两行**：合成一行要多一个中间页，且后端不给工单未读数，定稿上的红点画不出来。两行与原有标识、UI 用例一致。
4. **方块颜色**：六个深色值写在新文件的具名常量里，单测逐个算白字对比度 ≥ 4.5:1；亮暗同值（白字在深底上两档都成立）。
5. **单列门槛** `dynamicTypeSize >= .accessibility3`，抽成纯函数单测。
6. **实名认证 / 资质审核只读**：定稿上带箭头，但没有新去处（资质证书方块已经进证书页，标识不能重复），做成值行。

## Risks / Trade-offs

- UI 用例里直接在「我的」找退出登录 / 删除账户 / 个人资料 / 隐私 / 拉黑的，要先点头像卡 → 统一走一个辅助函数，只改陪跑员侧用例。
