## Why

陪跑员接单开关开着（服务端可服务）、手上有一张出发 / 汇合 / 跑步中的单、本机又没有陪跑员位置轨迹同意时，「自动恢复待命」和「同行态」两处会同时盖出同一张同意页（issue #420）。拒绝最上面那张后它收起，露出底下一模一样的另一张：读屏用户被同一个问题问两次，且拒绝之后界面看起来没有反应。

## What Changes

- 两处同时要问时只问一次：同行态那张（盖在整个界面上）优先，同行态期间不再弹「自动恢复待命」那一问；已经弹出的恢复待命 / 接单开关同意页在同行态开始问时收起。
- 在同行态那张上同意：同意记录本来就是同一条，接单待命照常恢复，不另问。
- 在同行态那张上拒绝，两处都算拒绝（负责人 2026-10-15 定）：这一单不共享位置（与现有行为相同，横幅显示并播报同行态那一句），同时替陪跑员关掉服务端接单开关，滑块上方留下「没有开始接单……」那一句但**不念**（只念一句，避免两句播报互相切断），本次登录不再追问恢复待命。
- 「自动恢复待命」那一问改为等首份接单摘要到达、知道手上有没有同行态的单之后再判，避免冷启动时先闪出一张再收起。

## Capabilities

### New Capabilities

（无）

### Modified Capabilities

- `location-track-consent`：「志愿者接单开关与自动恢复待命前先问」加上与同行态同意页的去重与拒绝联动。

## Impact

- `blindRun/Core/LiveEscortSessionCoordinator.swift`：同步判「这一单要不要问」，并把「开始问」「拒绝」两件事告诉陪跑员首页。
- `blindRun/Volunteer/VolunteerHomeView.swift`（`VolunteerHomeViewModel`）：恢复待命那一问让给同行态；同行态拒绝时关接单开关。
- 测试：`blindRunTests/LocationTrackConsentTests.swift`、`blindRunUITests/AccessibilityAuditTests.swift`。
- 不涉及后端契约。
