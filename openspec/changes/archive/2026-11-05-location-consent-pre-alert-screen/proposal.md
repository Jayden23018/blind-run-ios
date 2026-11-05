## Why

负责人 2026-11-05 要求同意弹窗参考苹果 HIG 隐私页（https://developer.apple.com/design/human-interface-guidelines/privacy ）再改一轮（Jayden23018/blind-run-ios#776）。HIG「Pre-alert screens」一节：系统权限弹窗前的自定义说明页只放一个按钮，用「继续」而不是「允许」，按钮的作用是打开系统弹窗；除非为了取得法律同意，不放取消或关闭。位置轨迹的三处同意（预约前、志愿者接单开关、陪跑中同行态）正好排在系统定位授权框之前，#771 的「左不同意、右同意」小弹窗与这一节冲突。

## What Changes

- 位置三处改成系统弹窗前的说明页：整页，标题 + 三条带图标的用途 + 保存期限与「可以随时在系统设置里关闭定位」+「查看详细说明」（逐条告知原文）+ 唯一按钮「继续」。
  - 系统定位还没决定时：「继续」弹系统定位框；选「允许」记同意，选「不允许」走原来的拒绝反馈。
  - 系统定位已决定、不会再弹系统框时：另给一个「不同意」（HIG 允许的法律同意例外），「继续」直接记同意。
  - 按钮不用「允许」「同意共享位置」这类字眼。
- 其余小弹窗（语音下单大模型、视力状况、行程分享）与首启弹窗：按钮改成上下排、整行铺满，同意在上。
- `NSLocationWhenInUseUsageDescription` / `NSLocationAlwaysAndWhenInUseUsageDescription` 按 HIG 改成主动句并说清志愿者派单这一用途。

## Capabilities

### Modified Capabilities

- `location-track-consent`: 同意界面改成系统弹窗前的说明页，系统定位框的回答就是这份同意。
- `consent-forms`: 小弹窗不再包含位置轨迹；小弹窗与首启弹窗的按钮改成上下排。

## Impact

- 新增 `LocationTrackPreAlertView`（三处共用）与 `PrivacyConsent+LocationPreAlert.swift`（说明页文案）；`LocationService.requestPermission` 多一个参数，让说明页在记同意之前弹系统框而不撞调试断言。
- 告知原文 `disclosures` 与 `disclosureVersion` 不变，老用户的同意记录照常有效。何时问、按账号记、同行态拒绝的后果都不变。
- UI 测试里位置同意的「同意」按钮 identifier 改成 `…ContinueButton`。
