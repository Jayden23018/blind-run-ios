# 精确位置关闭时，下单页怎么提示（#813）

调研日期 2026-11-11。问题：盲人关了「精确位置」，约跑页该用什么形态提示，才不丑、不长。

## 查到的
- **Apple 文档**（`CLLocationManager.requestTemporaryFullAccuracyAuthorization(withPurposeKey:completion:)`，2026-11-11 经 developer.apple.com 的 JSON 地址取回）：
  可申请一次临时精确位置；用户允许后，App 在前台一直有效，直到权限自动过期；
  App 在后台、已有精确权限、Info.plist 没有对应用途键时，请求一定失败；
  失败时「记录错误，下次用户再做那个需要精确位置的动作时重试」。
- **HIG 隐私页**（经搜索摘要，没读原页）：等用户用到需要权限的功能时再请求；需要多解释可在系统框前放一个自定义页。
- **Uber 帮助页**（help.uber.com，经搜索摘要）：选「大致位置」仍能叫车，但上下车地址要自己输入。
- **Radar 博客**：只给了大致位置的用户，在导航、路边取货等具体功能处再申请临时精确位置。

## 真机弹窗实测（2026-11-12，iOS 26.2 模拟器 iPhone 17 Pro）
用一个临时小 App（Info.plist 里放本仓库同一段用途说明）在「精确位置」关闭时调 `requestTemporaryFullAccuracyAuthorization`，真弹出的系统框：
标题「允许“助盲跑”使用你的精确位置一次？」，正文是用途说明原文，两个胶囊按钮「不允许」「允许一次」，没有地图。
截图：`docs/ui/mockups/booking-gate-20261111/system-temp-precise-prompt-ios26.png`。
同一个 App 第一次要定位权限时的框是另一种（「允许一次 / 使用 App 时允许 / 不允许」三个按钮）。
精确位置还开着时调用，直接回调 `kCLErrorDomain Code=18`，不弹窗（模拟器日志实测）。

## 没查到的
滴滴、美团、高德、Lyft、DoorDash 在精确位置关闭时的真实界面：搜不到文字说明，没有截图。不能说「别家都这样做」。

## 结论
用户点「开始找陪跑员」时直接请求临时精确位置（系统框，读屏原生支持）；被拒后给一个短提示，出路是「选常用地点」「去设置」。
本仓库已有 `LocationService.requestTemporaryPreciseLocationAndWaitForAnswer(for:)` 与 Info.plist 用途键 `AidRunBookingStartPoint`。

## 复核触发条件
Apple 改临时精确位置的行为；拿到别家真机截图与结论不符。
