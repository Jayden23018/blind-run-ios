## Why

约跑页（#806 新版）在精确位置关闭时，出发点为空，点「开始找陪跑员」只念「请选择出发地点」，盲人不知道原因，也没有恢复入口（#813）。
现行规格要求页面显示一大段降级告知加两个按钮；负责人 2026-11-11 看过模拟图后不同意，要求改成直接弹系统权限框，页面保持简洁。

## What Changes

- 约跑页点「开始找陪跑员」时，若出发点是当前位置且精确位置关闭：直接请求一次临时精确位置（系统框）。允许则取位置并继续提交。
- 被拒后：应用弹一个短提示（原因 + 出路「选常用地点」「去设置」），可见并朗读。
- 定位权限被拒：不弹系统框（系统不会再弹），直接弹同样的短提示，出路相同。
- 出发点是常用地点：不拦，不提示。
- 页面：卡底小字说明状态；标题下一行显示后端下发的开放范围（`launchScope.areaHint`，已有规格，只是约跑页还没接）。
- 进页开场播报：定位用不了时，不再说「从当前位置出发」。
- **BREAKING（规格层面）**：删除「出发地点区块显示降级告知段落 + 『临时开启精确位置』『去设置』两个入口」的要求，改为上面的行为。

## Capabilities

### New Capabilities
（无）

### Modified Capabilities
- `blind-precise-location-gate`: 「精确位置关闭时下单不用当前位置作出发点」的告知形态与入口改变。

## Impact

- `blindRun/BlindRunner/BlindMatchFirstBookingView.swift`、新增 `BookingStartGate.swift`。
- 复用 `LocationService.requestTemporaryPreciseLocationAndWaitForAnswer(for:)`、`SystemSettingsLink.open()`、Info.plist 用途键 `AidRunBookingStartPoint`。
- 不碰后端契约。`booking-launch-scope` 的「限制显示在对应步骤」要求已存在，本次只是让约跑页满足它。
- 设计稿：`docs/ui/mockups/booking-gate-20261111/`；调研：`docs/research/precise-location-prompt-20261111.md`。
