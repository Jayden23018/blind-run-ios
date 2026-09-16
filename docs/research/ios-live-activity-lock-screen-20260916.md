# 锁屏实时活动：按钮能不能在不打开 App 的情况下发声？后台震动受什么限制？

2026-09-16 · 起因是设计交接包 `README.md` 「落地顺序建议」第 5 条对 D 组单列的一句：
「**先写 demo 验证**：后台震动受系统限制，可能要借本地通知；实时活动按钮点击后能否不打开
App 就发声也待验证」。本文是那个 demo 的结论。

**验证手段**：`/tmp/ladem` 里一个从零手写的两 target 工程（app + widget extension），跑
iPhone 17 Pro 模拟器（iOS 26.2 / Xcode 26.2）。**为什么不在本仓库验**：高德 SDK 没有
arm64-sim slice，本仓库的模拟器通道永久不可用，而实时活动的锁屏表现在真机上我看不见
（没有真机截屏通道）。demo 是唯一能拿到可粘贴证据的路。

---

## 一句话结论

**能。** 锁屏卡上的按钮按下之后，系统在 **app 进程**里执行意图、App 不打开、屏幕不亮，
音频会话激活成功，`AVSpeechSynthesizer` 真的念出来了。**不需要** `UIBackgroundModes: audio`。

---

## 1. 官方口径（先查文档再动手）

三处，逐条注明出处与核实日期（2026-09-16 当天拉的 `developer.apple.com` 文档 JSON）：

| 事实 | 出处 | 原文 |
|---|---|---|
| `Activity` 自 iOS **16.1** 起 | `activitykit/activity` | platforms: iOS 16.1 |
| `LiveActivityIntent` / `AudioPlaybackIntent` 自 iOS **17.0** 起 | 同名文档页 | platforms: iOS 17.0 |
| 采用这两个协议的意图在 **app 进程**里执行 | `widgetkit/adding-interactivity-to-widgets-and-live-activities` | 「If you adopt the LiveActivityIntent or AudioPlaybackIntent protocol, the system runs the app intent in the app's process. Make sure to add your custom app intent to your app target.」 |
| 默认（裸 `AppIntent`）在 **widget 进程**里执行 | 同上 | 「By default, the system runs the app intent in the same process as the widget extension.」 |
| 系统会为了执行意图而**启动 app 进程但不打开 App** | `appintents/liveactivityintent` | 「the system launches your app process without opening the app, performs the intent」 |

⚠️ **同一页还有一句必须原样记下来，因为它是这块唯一的坏消息**：

> 「On a locked device, buttons and toggles are inactive and the system doesn't perform actions
> unless a person authenticates and unlocks their device.」

即：**设备处于「已锁且未认证」时，锁屏卡上的按钮是不响应的。** Face ID 机型上用户看一眼就
完成认证（此时人还停在锁屏界面上，按钮可用），但**手机在臂带 / 口袋里、脸没对着屏幕**时，
按钮按下去不会有任何反应。这一条对盲人跑者不是边缘情况 —— 见下面「未决」。

## 2. demo 实测（2026-09-16，iPhone 17 Pro 模拟器）

证据落盘在 app 容器的 `Documents/probe.log`，原样粘贴：

```
[2026-09-16T13:03:36Z] areActivitiesEnabled=true
[2026-09-16T13:03:36Z] 实时活动已启动 id=ABE6CBCE-D90B-4CBB-998E-97FCB03D5C9D
[2026-09-16T13:04:24Z] intent.perform 进入，bundle=com.zwaidrun.lademo process=LADemo
[2026-09-16T13:04:24Z] audioSession 激活成功（category=playback）
[2026-09-16T13:04:24Z] synthesizer.speak 已调用，isSpeaking=false
[2026-09-16T13:04:24Z] haptic 已调用
[2026-09-16T13:04:24Z] ✅ didStart —— 真的开始念了
[2026-09-16T13:04:25Z] 1 秒后 isSpeaking=true
[2026-09-16T13:04:30Z] ✅ didFinish —— 念完了
```

逐条能推出什么：

1. **`bundle=com.zwaidrun.lademo` / `process=LADemo`** ⇒ 意图确实在 **app 进程**里跑的，
   不是 widget 进程（widget 的 bundle id 是 `...lademo.widget`）。官方那句话成立。
2. **按下按钮之后截图仍停在锁屏**（App 没有被打开）⇒「不必解锁」那一半成立。
3. **`audioSession 激活成功`** ⇒ 后台激活 `.playback` 没有被系统拒绝。
4. **`didStart` / `didFinish` 都回调、`isSpeaking` 1 秒后为 true** ⇒ 真的在念，不是
   「调用了但被静默丢弃」。
   > 🚩 `speak()` **之后立刻**读 `isSpeaking` 恒为 `false`（异步起播）。只看那一行会得出
   > 「没念」的反结论 —— 判「有没有真的出声」必须挂 delegate 或延后再读。

### 2.1 `UIBackgroundModes: audio` 不需要

做了 A/B：把 demo 的 `Info.plist` 里 `UIBackgroundModes` 整个键删掉、重装、重跑同一条路径，
上面那份日志是**删掉之后**跑出来的 —— `didStart` / `didFinish` 照常。

⇒ **不要给主 App 加 `audio` 后台模式。** 那是一条会被审核问到、且这里用不上的后台模式。

### 2.2 后台震动

demo 里 `UINotificationFeedbackGenerator` 调用没有崩、没有报错，但**模拟器没有振动马达，
日志只能证明「没崩」，证明不了「响了」**。这一条留给真机人工确认（见「未决」）。
D 组两屏的规格里没有任何震动要求，所以它不阻塞本阶段。

### 2.3 顺带撞到的四条（都会浪费下一个人的时间）

1. **重装 App 会把正在进行的实时活动杀掉。** 开发期改一行代码重装，锁屏卡就没了，
   看起来像「代码把它弄坏了」。要重新从 App 里起一次。
2. **系统会问两次授权**：第一次「Allow Live Activities from X?」，下一次变成
   「Do you want to continue to allow…? / **Always Allow**」。两次都弹在锁屏上、盖住卡片下半。
3. **卡片主体是深链接**：点在按钮以外的任何地方 = 打开 App。按钮只占卡片下半，
   手指没对准就会把 App 打开 —— 对看不见屏幕的人这是高频误触面。VoiceOver 用户按元素
   逐个划过去不受影响。
4. **卡片高度上限约 175pt**（iPhone 17 Pro 实测）。把按钮从 52pt 拉到 110pt 时，
   顶行「陪跑中 · 张伟」当场被裁掉且没有任何警告。全屏那套 82/36 的字号放不进来。

## 3. 落到本仓库的结论

- 意图用 `AudioPlaybackIntent`（不是裸 `AppIntent`，那个在 widget 进程里跑、没有音频会话）。
- 意图类型必须**同时**在 app target 与 widget target 里编译（app 侧是执行处，
  widget 侧是 `Button(intent:)` 的编译依赖）。
- 卡片尺寸用状态清单 §16 那套缩小值（56 / 24 / 15 / 13，按钮 52），不用全屏那套。
- `Info.plist` 只加 `NSSupportsLiveActivities`，**不加** `UIBackgroundModes: audio`。
- widget target 部署目标 16.2（`ActivityContent` 起点），按钮 `#available(iOS 17.0, *)`。

## 4. 未决（本轮没能验的两件，都要真机人工做）

1. **「已锁且未认证」时按钮到底响不响。** 官方文档说不响；模拟器没有密码锁，复现不了那个状态。
   这决定了「手机在臂带里、盲人伸手按一下就能听到数据」这个设计承诺成不成立。
   👉 真机验法：设好密码锁 → 起一单 `IN_PROGRESS` → 锁屏 → **用手遮住原深感摄像头**
   （避免 Face ID 认证）→ 按「播报当前数据」→ 听有没有声音。
2. **后台震动到底响不响。**（本阶段不依赖，阶段 2 的四种提示音会依赖。）

---

**复核触发条件**：iOS 大版本改实时活动的交互授权口径（尤其上面那句「locked device」）；
Apple 调整 `AudioPlaybackIntent` / `LiveActivityIntent` 的执行进程；实时活动高度上限变化。
