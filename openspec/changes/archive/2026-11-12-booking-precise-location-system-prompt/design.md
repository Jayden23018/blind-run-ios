## Context

负责人看过 v1（出发地点下方一大段说明 + 两个按钮）后否决，要求「直接弹权限框，或跳设置，不要大段说明」。
苹果文档建议在用户做了需要精确位置的动作时再请求；系统不弹时（已有精确位置、后台、用途键缺失）回调带错误。
真实系统框已在 iOS 26.2 模拟器核对：标题、「不允许 / 允许一次」按钮为系统原样，正文是 Info.plist 用途说明（`docs/ui/mockups/booking-gate-20261111/system-temp-precise-prompt-ios26.png`）。

## Decisions

- **触发点是提交，不是进页。** 进页时开场播报正在说话，系统框会抢走读屏焦点（`BlindBookingViewModel+StartLocation` 注释已记）。
- **判定抽成纯函数** `BookingStartGate.evaluate(usesCurrentLocation:isDenied:isPreciseLocationOff:)`，便于单测；视图只做执行。
- **被拒提示用 SwiftUI `.alert`**：系统样式、读屏原生；「去设置」走现成 `SystemSettingsLink.open()`。
- **允许后直接继续提交**，不让用户再点一次；位置取不到时落回原有「请选择出发地点」。
- 开放范围一行读后端 `launchScope.areaHint`，城市不写死；没有限制不显示。

## Risks

- 允许后紧接着取位置：授权回调可能晚于 completion，`requestTemporaryPreciseLocationAndWaitForAnswer` 已在回调后同步精度授权。
- 被拒提示与读屏系统 alert 播报可能重复：提示出现时只朗读一次应用自己的句子，与现有 `speakError` 惯例一致。
