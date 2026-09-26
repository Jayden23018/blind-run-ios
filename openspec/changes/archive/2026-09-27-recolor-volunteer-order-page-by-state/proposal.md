## Why

陪跑员订单页 v1（PR #210–#216）除邀请外头卡统一藏青，头卡上的文字色、引导绳配色都是专为藏青调的。交付包 v2（`~/Downloads/zhumangpao-handoff-v2/`，决定源 `DECISIONS-v2.md` V2 ③④⑤、V4、V11、V13）改为**头卡按状态着色**，让陪跑员扫一眼就知道这一单走到哪了；同时补齐 v1 欠下的动画、触感与 Preview。

## What Changes

- **BEHAVIOR CHANGE（视觉）**：头卡底色按状态变化 —— 约好 / 跑者取消藏青、出发主蓝、汇合琥珀、完成绿；每次状态切换头卡底色做 0.35 秒过渡（C01、C05）。
- 头卡文字改为通用的半透明白（`onHero*`），引导绳改为白色系（陪跑员白色实心、姓氏用当前状态色；跑者白描边；绳子 75% 白），金色调亮为 `#FFD978`（C02–C04、C10）。
- 汇合页方位盘、响铃按钮、④b 的「打电话」改琥珀色系（C07–C09）。
- 删除 `onNavy*`、`volunteerDot`、`runnerDot`、`ropeOnNavy`、`mutedOnNavy`、`mutedStrokeOnNavy`（C12）。
- 动画对齐 `03-motion-and-haptics.md` §二：出发中 ETA 更新 easeOut 0.6 秒、汇合时方位盘 0.9 倍缩放淡入、②→②b 主按钮原地升级、进入完成页插图放大淡入 + 金色绳画出；「减弱动态效果」下全部退为不超过 0.2 秒的淡入淡出，没有位移和缩放。
- 触感对齐 §五：接下邀请成功 `.success`（此前没有）。
- `docs/ui/design-direction.md` 允许陪跑员订单页头卡使用状态色（V13）。

不在本变更：跑步中页面（V4，布局不动）、锁屏实时活动（FE-2）、姓氏字段（BE-2 未合，继续用掩码）、完成页留言卡与志愿时长卡（v1 没做，另立 issue）。

## Capabilities

### Modified Capabilities
- `volunteer-order-page`: 头卡按状态着色并过渡；「减弱动态效果」下状态切换没有位移与缩放。

## Impact

- 代码：`blindRun/Core/DesignSystem/FlowPalette.swift` `FlowV2Components.swift`、`blindRun/Volunteer/RopeView.swift` `DirectionDial.swift` `VolunteerOrderFlowPage.swift` `VolunteerOrderV2.swift`、`VolunteerHomeView.swift`（接单成功触感一行）。
- 共享色：`AppColors.Flow.gold` 取值变化，只有陪跑员订单页引用。
- 文档：`docs/ui/design-direction.md` §6.1。
