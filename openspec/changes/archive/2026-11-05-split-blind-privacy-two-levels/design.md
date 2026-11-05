## Context

现状见 proposal.md。第一层 `PrivacyAuthorizationView` 持有视力那项的 `BlindRunnerProfileViewModel`（撤回走它的 `withdrawVisionConsent()` / `submit()`，`ProfileModule.swift` 由 #750 在改，本变更只调用）。语音、位置两项的同意状态是 `AppState` 上现读的计算属性，SwiftUI 收不到变化通知。

## Goals / Non-Goals

**Goals:** 照定稿 `docs/ui/mockups/blind-privacy-20261105/privacy-final.png` 拆两层；复用 `GroupedCard`、`GroupedCardDivider`、`GroupedCardFootnote`、`SettingsChevron`。

**Non-Goals:** 陪跑员端页面；撤回逻辑、同意记录、文案含义；按钮组件（#749）。

## Decisions

1. **详情页自己持有结果状态。** 语音、位置两页各自读 `AppState`、各自存撤回结果和刷新计数。比把结果存在第一层再传进去稳：不依赖父视图重算时推入页跟着刷新。视力那页用 `@ObservedObject` 接第一层的 view model，待保存、失败那两种状态本来就存在 view model 里。
2. **第一层出现时刷新一次。** 从详情页返回时 `onAppear` 自增刷新计数，列表重读计算属性，状态行就是最新的。
3. **结果分成功与其他两类上色。** 成功：绿字 + 对勾；被拦 / 失败：正文色 + 叹号图标。颜色不是唯一区分，句子本身说清了结果。
4. **状态文案拆成「短值 + 补充说明」。** 「当前」行右侧放短值（已同意 / 没有同意 / 撤回还没完成），原来句子里的补充说明一字不改地放到状态卡下面当组说明。资料未加载那句原样放在撤回行的位置（没有撤回行，和现状一样）。
5. **视力撤回行改名「撤回视力状况和导盲犬的同意」**，和另两项同一句式；失败提示里「再点一次」的按钮名跟着用这个名字。读屏标签沿用 `VisionConsentWithdrawalCopy.accessibilityLabel`，撤回行另挂 `accessibilityInputLabels` 写可见标题，语音控制按可见标题能找到。

## Risks / Trade-offs

- [UI 用例多一层导航，入口行在最大字号下可能在屏外] → 进详情页前先滚动到行再点。
- [负责人 2026-11-05 定本次不跑测试] → 只跑 build-for-testing，PR 写明未跑测试，由负责人自己验。
