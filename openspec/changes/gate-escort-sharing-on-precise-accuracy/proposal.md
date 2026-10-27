## Why

#380（#373）只在盲人端的求助与下单起点拦住「精确位置」关闭时的区域代表点（约 5 公里偏差）。陪跑中的同行位置照样每 5 秒上报这个点：
陪跑员地图、距离告警都按它算，约 5 公里的偏差会让距离告警误报；服务端存下的模糊点还会被「播报我的位置」兜底读到（#406 留下的两个窗口）。
项目负责人 2026-10-28 定（Jayden23018/blind-run-ios#407 第 2 项）：**拦截** —— 不传比传错位置更诚实。第 3 项（语音下单消歧）定为保持现状。

## What Changes

- **陪跑同行位置（两端）**：精确位置关闭时不上报区域代表点，同行位置暂停共享；精确位置恢复后自动恢复。此前只拦了盲人端的求助与下单，同行位置照发。
- **健康横幅（两端）**：「精确位置已关闭」一档对陪跑员也生效，文案按角色说清后果（对方看不到你的位置），横幅可见并播报（沿用根视图对健康档位的播报）。
  盲人端文案改为说清「已暂停同行位置共享」，不再说「陪跑员可能看不到准确位置」。
- **临时精确位置（两端）**：同行会话出发时（`DRIVER_EN_ROUTE`）精确位置关着就申请一次，进入 `IN_PROGRESS` 时仍关着再申请一次，同一单同一阶段不重复。
  陪跑员端用自己的用途说明（新增 `Info.plist` 键 `AidRunEscortVolunteer`），不借用盲人那条（那条讲的是「求助才能带上你的准确位置」）。
- **语音下单消歧（#407 第 3 项）**：保持现状，继续传大致位置只做就近消歧、不当出发点。理由写进 design。
- 不改后端契约。

## Capabilities

### New Capabilities
- `escort-precise-location-gate`: 陪跑同行位置在「精确位置」关闭时两端都不上报，可见可听地告知，并在会话开始时申请临时精确位置。

### Modified Capabilities

## Impact

- `blindRun/Core/LiveEscortSessionCoordinator.swift`：发送闸、健康判定、临时精确位置申请去掉「只限盲人」。
- `blindRun/Map/LocationService.swift`：`PreciseLocationPurpose` 加陪跑员用途；`LocationError.preciseLocationOff` 的注释更新。
- `blindRun/Info.plist`：`NSLocationTemporaryUsageDescriptionDictionary` 加 `AidRunEscortVolunteer`。
- 同一事实在未归档的 `gate-blind-location-on-precise-accuracy` 里写的是「陪跑员端不变、不停发同行位置」，一并改成指向本变更。
- 测试：`PreciseLocationGateTests` 增补两端的发送闸、横幅文案与临时精确位置申请。
