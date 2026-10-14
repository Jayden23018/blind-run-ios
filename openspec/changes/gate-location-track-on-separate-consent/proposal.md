## Why

首启告知（`PrivacyConsentPurpose.appLaunch`）承诺「身份证号、人脸、位置轨迹和视力状况……到收集它们的那一步，我们会再单独问你一次」，
而 iOS 只有身份证号 / 人脸 / 视力状况三项单独同意，**位置轨迹从没单独问过**（PIPL 第 29 条，Jayden23018/blind-run-ios#368）。
安卓已按负责人同意的方案实现并经两轮安全审查定稿（Jayden23018/blind-run-android#55，PR #201），iOS 逐字同步。

## What Changes

- 新增两项单独同意 `blindLocationTrack` / `volunteerLocationTrack`（version 1），文案与安卓逐字一致。按账号记；后端不存这项同意，本机没有记录就当没同意过。
- **盲人预约**：预约向导路由本身过闸。没有记录 → 先盖同意页；拒绝 → 回首页，念并留下后果说明，不能预约。首页不再在进页时弹系统定位授权框。
- **志愿者接单开关**：滑开时没有记录 → 盖同意页，开关不翻、不发请求；同意 → 弹系统授权框、打开开关、进接单主页；拒绝 → 开关保持关，滑块上方留下后果说明。
- **志愿者自动恢复待命**：服务端「可服务」开着、本机没有记录 → 先问；拒绝 → 替他把服务端开关关掉。
- **派单定位**：只在开着接单开关、且有同意时为派单上报位置（同意文案第 1 条「暂停接单后不再为派单获取位置」的兑现）。
- **同行态**（`DRIVER_EN_ROUTE` / `DRIVER_ARRIVED` / `IN_PROGRESS`）：没有记录 → 不开定位、不上报，根视图盖同意页；拒绝 → 这一单不再问，横幅显示并播报后果。
- **求助**：同行态里没有同意时求助不附位置，按「拿不到坐标就不发」处理，文案说清原因并给 120 / 110。
- 同意页出现前不弹系统定位授权框（告知在前）。
- 不改后端契约。

## Capabilities

### New Capabilities
- `location-track-consent`: 两端开始持续定位前取得位置轨迹的单独同意，以及拒绝后的行为。

### Modified Capabilities

## Impact

- 代码：`blindRun/Core/PrivacyConsent.swift`、`AppState.swift`、`LiveEscortSessionCoordinator.swift`、`blindRun/ContentView.swift`、
  `blindRun/BlindRunner/BlindRunnerHomeView.swift`、`BlindOrderStatusView.swift`、`blindRun/Volunteer/VolunteerHomeView.swift`、
  `VolunteerTabView.swift`、`VolunteerOrderFlowViews.swift`、`blindRun/Safety/EmergencyCoordinator.swift`、`SafetyModule.swift`、`blindRun/Map/LocationService.swift`。
- 测试：`blindRunTests/` 新增同意闸、协调器、志愿者开关、求助用例；`blindRunUITests/` 新增两端发起前的同意页用例。
- API / 契约：无。
- 已知代价：暂停接单的志愿者不再上报位置，后端 `DeparturePlanner` 估算出发时用的是最后一次上报的位置（与安卓一致）。
