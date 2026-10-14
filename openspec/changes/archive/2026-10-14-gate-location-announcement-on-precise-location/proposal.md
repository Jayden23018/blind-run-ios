## Why

系统「精确位置」关闭时（`reducedAccuracy`），本机坐标是约 5 公里范围的区域代表点。「播报我的位置」仍把它逆地理成地名念出来，而这句话会被用户逐字转述给 110 / 120 —— 偏几公里的地名比「拿不到位置」更糟（#406，来源 #380 合并前的安全复核 #405）。服务端兜底 `GET /api/orders/{id}/location/address` 读的是同行位置上报，精确位置关着时上报的也是模糊点，所以兜底同样不准。

## What Changes

- 精确位置关闭时，「播报我的位置」不逆地理、不请求服务端兜底，直接念固定文案（负责人 2026-10-14 选定方案①）：
  「「精确位置」已关闭，只能拿到大致位置，可能偏差几公里，所以念不出你的准确位置。请直接拨打120或110，说明你周围的情况；跑完后可在系统设置里为助盲跑打开「精确位置」。」
- 这一路径不申请临时精确位置：系统框会在紧急时刻抢走读屏焦点，陪跑的出发与开跑两个时刻已各申请过一次（#380）。
- 精确位置开着时行为不变。

## Capabilities

### New Capabilities

（无）

### Modified Capabilities

- `blind-runner-voice-first-experience`: 「Location announcement falls back to the server and states its age」增加精确位置关闭时的分支。

## Impact

- `blindRun/BlindRunner/BlindOrderStatusView.swift` `BlindOrderStatusViewModel.announceCurrentLocation()`
- `blindRun/Safety/SafetyModule.swift` `EmergencySafetyCopy` 新增一条文案
- `blindRunTests/LocationAddressAnnouncementTests.swift` 新增用例
- 不改 WebSocket 位置上报、陪跑员代发求助（#407）。无 API 契约变更。
