## Why

陪跑员首页「我的预约」区块里那张预约卡（`SCHEDULED_CONFIRMED` 的「确认我还会去 / 我去不了」）还是旧格式：系统蓝 `PrimaryButton`、粉底红字的「我去不了」（只有 52pt）、系统 `confirmationDialog`。它和订单页 v2「约好」屏做的是同一件事，长得却不一样（iOS #463）。负责人 2026-10-17 拍板：样式照订单页 v2「约好」屏；「我去不了」保留二次确认（释放已接的单不可逆，不跟 v3 邀请卡的「5 秒撤销」），确认层与 App 内其他不可逆操作一致。

## What Changes

- 预约卡改用订单页 v2 的组件：卡片取行卡的底色 / 圆角 / 阴影；主按钮 `FlowActionButton(.raisedPrimary)`；「我去不了」是灰字 `FlowTextButton`，可点区 64pt；放行时刻小字摆在主按钮正上方。
- `PENDING_ACCEPT` 卡上的「打开订单页」用白色次要按钮（订单页解锁前「我已经出发了」同一个样子）。
- 「我去不了」的确认改用订单页同一个底部弹层 `VolunteerCancelSheet`（文案来自 `VolunteerOrderFlowCopy.cancelSheet`，含窗口内「会记一次临时取消」）。
- `FlowTextButton` 加可选 `minHeight`（默认仍 44，订单页不变）。
- 保留 `volunteerScheduledConfirm-*` / `volunteerScheduledRelease-*` 两个 identifier。

## Impact

- `blindRun/Volunteer/VolunteerHomeView.swift`（`VolunteerScheduledOrdersSection`）、`VolunteerProfileFirstScreenView.swift`（传入规则参数）、`blindRun/Core/DesignSystem/FlowV2Components.swift`（`FlowTextButton.minHeight`）
- `docs/ui/mockups/INDEX.md` 补一行
- 无契约改动
