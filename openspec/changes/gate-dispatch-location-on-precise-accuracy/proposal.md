## Why

陪跑员开着接单开关时，App 为派单上报位置（根视图定时上报、`VolunteerLocationReporter` 在开开关 / 接单时补报）。这条路径不判系统「精确位置」开关：关着时照发约 5 公里偏差的区域代表点，服务端按它算「附近的陪跑员」与 ETA，陪跑员会被派到几公里外的单，或该派的没派到（Jayden23018/blind-run-ios#520）。`gate-escort-sharing-on-precise-accuracy`（#407）把同行位置拦住了，派单这条留在它的 Non-Goals 里另开 issue。

## What Changes

- 精确位置关闭时，派单位置一律不上报（两条路径都拦）。
- 陪跑员开着接单开关、精确位置关着时：顶部常驻一句原因（已暂停为派单上报、附近的邀请会收不到、怎么恢复），出现时念一次，并申请一次临时精确位置（新用途键 `AidRunVolunteerDispatch`）。
- `PreciseLocationPurpose` 改为 `CaseIterable`，用例逐个核对 `Info.plist` 里都有用途说明。

## Capabilities

### New Capabilities
- `dispatch-precise-location-gate`: 精确位置关闭时不为派单上报区域代表点，并可见可听地告诉陪跑员。

### Modified Capabilities

## Impact

`blindRun/Volunteer/VolunteerLocationReporter.swift`、`blindRun/ContentView.swift`（定时上报闸）、新文件 `DispatchPreciseLocationNotice.swift`（挂在 `VolunteerTabView`）、`blindRun/Map/LocationService.swift`、`blindRun/Info.plist`。
