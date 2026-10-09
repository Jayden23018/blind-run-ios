## Why

用户在系统定位授权里关掉「精确位置」后，iOS 把位置吸附到所在区域的一个代表点，精度约 5 公里
（iOS 26.2 SDK `CLLocationManager.h` 对 `CLAccuracyAuthorizationReducedAccuracy` 的注释，2026-10-09 核对）。
盲人端完全不识别这件事：云端求助照样把这个代表点当真实坐标上传，下单页照样把它当出发点。
读屏用户在授权弹窗里可能误关这个开关，而他们无法自己看出坐标不对（Jayden23018/blind-run-ios#373，上线前审计 M3）。

## What Changes

- `LocationService` 读取并发布 `accuracyAuthorization`，提供「精确位置已关闭」判定和临时申请精确位置的入口。
  `Info.plist` 加 `NSLocationTemporaryUsageDescriptionDictionary`（下单起点、陪跑两条用途说明）。
- **云端求助**：精确位置关闭时不发，按「拿不到坐标」处理，可听可见地说「求助未发出：精确位置已关闭……请直接拨打110或120」。
  精确授权下样本精度差于 50 米时照发，但状态文案与播报加一句「求助附带的位置误差约 N 米……请同时直接拨打110或120」。
- **下单起点**：精确位置关闭时不再把当前位置当出发点，改走与「定位被拒」同一套可听可见的降级告知，
  提供「临时开启精确位置」与「去设置」按钮，搜索 / 常用地点照常可用。精确授权下精度差于 50 米时仍可用当前位置，
  但当前位置卡片加一句「定位精度较低，请核对地址」并念一次。
- **陪跑中（盲人端）**：出发去会合时若精确位置关闭，申请一次临时精确位置，进入 `IN_PROGRESS` 时仍关着再申请一次；会话健康横幅新增一档
  「精确位置已关闭」，可见且播报，说清求助会发不出去。
- 志愿者端：不拦截、不申请临时精确位置、不进新的健康档位（它的求助取坐标不经过 `freshEmergencyCoordinate`）。
  唯一的连带变化：求助协调器两端共用，陪跑员发求助时所附坐标差于 50 米也会附上同一句误差说明。
- 不改后端契约。

## Capabilities

### New Capabilities
- `blind-precise-location-gate`: 盲人端识别「精确位置」关闭与低精度定位，并据此约束云端求助、下单起点与陪跑中的告知。

### Modified Capabilities

## Impact

- 代码：`blindRun/Map/LocationService.swift`、`blindRun/Safety/EmergencyCoordinator.swift`、`blindRun/Safety/SafetyModule.swift`、
  `blindRun/Safety/EmergencyCountdownView.swift`、`blindRun/Core/LiveEscortSessionCoordinator.swift`、
  `blindRun/BlindRunner/BlindBookingView.swift`、`BlindOrderStatusView.swift`、`BlindRunnerHomeView.swift`、`BlindActiveRunView.swift`、`blindRun/Info.plist`。
- 测试：`blindRunTests/` 新增用例覆盖求助、下单、陪跑健康三条分支。
- API / 契约：无。求助请求体仍只有经纬度；要不要加精度字段留给后端另议。
- 与在途 PR #370 的重叠：只碰 `BlindBookingView` / `BlindOrderStatusView` / `BlindActiveRunView` 中 #370 未改的行段。
