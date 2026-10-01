## Why

后端 BE-2（blind-run-backend#452）已下发 `blindSurname` / `volunteerSurname`，口径是「用姓氏，缺失时退回『跑者』『陪跑员』，不拼先生/女士，不从掩码名截字」。iOS 只接了一半：锁屏卡姓氏恒为空、跑者端锁屏顶行把掩码名 `张*` 当名字显示（读屏念「张星号」）、`volunteerSurname` 解码后没有任何界面使用，出发/汇合卡也没有按 `activityState == .ended` 画结束样式（blind-run-ios#281）。

## What Changes

- 出发/汇合卡 `runnerSurname` 取 `blindSurname`；两端跑步卡的 `partnerName` 取对方姓氏（陪跑员端取 `blindSurname`、跑者端取 `volunteerSurname`），缺失时不显示名字，不再退回掩码名。
- 盲人端所有「朗读陪跑员」的通道（`volunteerNameForSpeech`）优先用 `volunteerSurname`；屏上可见的掩码名不变。
- 出发/汇合卡在 `activityState == .ended` 时画灰底「引导已结束」样式，无按钮、无引导绳。

不做：完成页「第 N 次」（等产品确认，#281 第 4 项）；跑步卡的 `isPaused` / `rhythmSignal` 接线。

## Capabilities

### New Capabilities

### Modified Capabilities
- `volunteer-live-activity`: 姓氏接线（含跑步卡）、新增「已结束」样式要求
- `blind-runner-voice-first-experience`: 朗读陪跑员时优先用 `volunteerSurname`

## Impact

`GuideRunActivityController.swift`、`LiveEscortSessionCoordinator.swift`、`VolunteerOrderFlowViews.swift`、`BlindOrderStatusView.swift`、`OrderDisplayHelpers.swift`、`GuideRunActivityShared.swift`、`GuideRunActivityWidget.swift` 及对应用例。无接口与契约变更。锁屏真实渲染无法在 XCUITest 里量，也拿不到 push token（#201），只验到编译 + 单测。
