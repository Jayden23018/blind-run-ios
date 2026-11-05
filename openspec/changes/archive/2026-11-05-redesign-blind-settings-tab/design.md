## Context

陪跑员「我的」已由 #712 改成头像卡 + 方块 + 列表，组件散在 `blindRun/Volunteer/VolunteerSettingsComponents.swift`、`VolunteerSettingsView.swift`（`VolunteerSettingsLayout`）、`VolunteerAccountPagesStyle.swift`。方块标签 `VolunteerSettingsTileLabel` 直接吃陪跑员的枚举，盲人端没法直接用。盲人端「我的」是 `List`。

## Goals / Non-Goals

**Goals:**
- 照定稿重排；入口与标识不丢（紧急呼叫行除外）；64pt；AX5 可用；白字对比度达标。
- 两端用同一套组件，不另写一套。

**Non-Goals:**
- 不改任何子页，不改 `BlindHomeSOSMode.resolve` 与 Magic Tap / 拨号单的挂载位置。
- 陪跑员端外观、行为、标识都不变。
- 不画后端没有的数据（工单未读红点）。

## Decisions

1. **通用组件挪进 `Shared/` 并改中性名字**：`SettingsTileLabel`（改吃 `title / systemImage / rgb`，不再吃陪跑员枚举）、`SettingsTileLayout`、`SettingsRowLabel`、`SettingsChevron`、`ProfileAvatarCircle`；分组卡 `GroupedCard`、`GroupedCardDivider`、`GroupedCardFootnote`、`GroupedCardMetrics`。陪跑员专用的值行、图标方块、小节标题留在原文件。只改名字和位置，不改实现。
2. **`ScrollView` + 分组卡，不用 `List`**：与陪跑员同理，方块网格放进 `List` 行里会互相抢点击。
3. **方块颜色复用陪跑员同名方块的色值**：固定搭档、邀请好友沿用陪跑员那两块；使用帮助取陪跑培训的绿，联系客服取资质证书的蓝。四色都已在真机审计里过过，单测再逐个算白字对比度。
4. **联系客服方块弹写字页**：与原来一样是 `sheet`，不是推入页。
5. **列表行最小高度用 64pt**：`SettingsRowLabel` 本来就是 `AppTouchTarget.blindPrimary`；通知行外框也给 64pt。
6. **账户页用 push，藏标签栏**：退出 / 删除进度遮罩挂在根视图上，sheet 会盖住遮罩（与陪跑员同一理由）。
7. **实名认证可点**：原来是可点行（实名是下单硬门槛，跳过后必须还能回到实名页），所以保留 `NavigationLink`，值显示当前状态。
8. **`AccountSafetySettingsRows` 删除**：改版后没有调用方。
9. **删掉「我的」紧急呼叫行**（负责人 2026-11-05 追加决定，用户在本会话里确认在本 PR 一起做）：
   `BlindProfileEmergencyRow`、`BlindSettingsEmergencyEntry`、`orderSafetyRequestForRow`、`profileRow*` 与 `.safetyHub` 只给这一行用，一起删。
   `OrderSafetyRequestPresenter`、`orderSafetyRequestForGesture` 给 Magic Tap 用，保留；标签栏容器上的 `.accessibilityAction(.magicTap)` 与 `.emergencyCallOptionsDialog` 不动。
10. **资料页保存栏挂 `blindProfileSubmitBar`**：资料页从账户页进入后标签栏跟着藏起来，毛玻璃保存栏贴到屏幕底，
    审计按坐标取到栏的颜色、误判对比度（记忆 `opaque-bottom-bar-fakes-contrast-failure`）。挂上 id 并登记进审计的遮挡栏列表。

## Risks / Trade-offs

- 非陪跑时 App 内没有可见的紧急拨号入口，只剩 Magic Tap（负责人已知并接受）。不开读屏的低视力用户在非陪跑时没有 App 内的拨号入口。

- 盲人侧多条 UI 用例要多点一下头像卡 → 统一走一个辅助函数 `openBlindAccountPage()`，每处只改一行。
- `blindRunUITests.swift` 正等着另一个任务（#723）拆分，本变更只改其中几行调用，冲突面小。
