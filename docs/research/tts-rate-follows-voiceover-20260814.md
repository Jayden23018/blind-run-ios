# App 自己的 TTS 播报能不能跟随用户的 VoiceOver 语速？

**日期**：2026-08-14
**起因**：`docs/review/blind-runner-full-review-20260812.md` §5.6 与 §6.1 #18 ——
`SpeechService.swift` 把 `utterance.rate` 写死成 `AVSpeechUtteranceDefaultSpeechRate`，
而代码注释（当时的 `:39-44`）自己写着「读屏用户常把语速调到 14~16 字/秒，合成器这边是写死的默认语速⋯⋯
不靠读代码拍板，真机听过之后再定」。这条问题在 review 里被排进「第二批：要产品拍板」。
**结论是：不需要拍板，平台已经给了答案。**

---

## 一句话结论

**读不到、也不该去读用户的 VoiceOver 语速；改设 `AVSpeechUtterance.prefersAssistiveTechnologySettings = true`，
由系统在 VoiceOver 运行时用用户自己的音色与语速覆盖我们写的值。** 该属性 `API_AVAILABLE(ios(14.0))`，
本仓库部署目标 16.0，**不需要 `#available` 分支**。出厂值是 `false`（实测），所以这是一个
「每一句播报都在犯」的存量缺陷，不是边界情况。

---

## 证据

### 1. 没有公开 API 能读到 VoiceOver 语速（且 Apple 是刻意的）

`SSAccessibility` 这个专门做这件事的开源库把限制写在自己的 README 里：用户能在设置里选语速，
但**没有编程接口拿到那个值**给 `AVSpeechSynthesizer` 用。它的绕法是干脆不用合成器，改走
`UIAccessibility` 通告，让 VoiceOver 自己念。

还有一层现实原因让「读一个值」这条路根本不成立：**用户面前有两个互相独立的语速滑块** ——
`设置 → 辅助功能 → 旁白` 的 Speaking Rate（还能按音色分别设）和 `设置 → 辅助功能 → 朗读内容`
的 Speaking Rate。没有单一的值可以被暴露。

### 2. 平台给的正解：`prefersAssistiveTechnologySettings`

**一手证据，本机 SDK 头文件原文**
（`iPhoneOS26.2.sdk/System/Library/Frameworks/AVFAudio.framework/Headers/AVSpeechSynthesis.h:207-210`）：

```c
/* If an assistive technology is on, like VoiceOver, the user's selected voice, rate and other settings
   will be used for this speech utterance instead of the default values.
   If no assistive technologies are on, then the values of the properties on AVSpeechUtterance will be used.
   Note that querying the properties will not refect the user's settings. */
@property(nonatomic) BOOL prefersAssistiveTechnologySettings API_AVAILABLE(ios(14.0), watchos(7.0), tvos(14.0), macos(11.0));
```

三件事一次说清，且都直接决定了我们的写法：

1. **VoiceOver 开 → 用用户的音色 + 语速**，正是我们要的。
2. **VoiceOver 关 → 仍用我们设的属性** ⇒ `AVSpeechSynthesisVoice(language: "zh-CN")` 和 `rate`
   那两行**必须保留**，删了会把低视力用户和明眼陪同者的中文音色一起丢掉。
3. **`querying the properties will not reflect the user's settings`** ⇒ 读 `utterance.rate`
   永远读回我们写进去的 0.5，**真实语速在进程里测不出来**。单测只能断言开关本身。

> ⚠️ **一处必须记下的纠错**：`WebSearch` 的结论摘要说这个属性是 **iOS 16+**。**是错的**，
> 头文件写的是 `ios(14.0)`。差别不影响本仓库（部署目标 16.0，两种说法都不用 `#available`），
> 但按 16+ 写会平白多一个永真的 `if #available` 分支。**版本敏感的 API 一律以本机 SDK 头文件为准，
> 不采信搜索转述** —— 这与全局 `CLAUDE.md`「不凭记忆写签名」是同一条。

### 3. 出厂值实测（不是推测）

`/tmp/pats_check.swift`，`swift pats_check.swift` 直接跑：

```
default prefersAssistiveTechnologySettings = false
after set = true
DefaultSpeechRate = 0.5 min = 0.0 max = 1.0
readback rate = 0.5
RESULT: PASS
```

两条都要：**出厂 `false`** 证明缺陷真实存在；**设完读得回 `true`** 证明用例断言得了这个开关
（头文件那句「查询属性反映不出用户设置」说的是 `rate` / `voice` 那几个，不是这个布尔本身）。

### 4. 顺带核实：`rate` 的标度是非线性的，中点是 0.5 不是 1.0

`AVSpeechUtteranceDefaultSpeechRate = 0.5`，`Minimum = 0.0`，`Maximum = 1.0`（上面实测输出）。
WWDC 2018 Session 236：0→0.5 对应约 0×→1× 语速，0.5→1 对应 1×→4×。
**所以任何「按百分比调语速」的手写映射都必须以 0.5 为中点分段**，直接把百分比乘上去是错的。
这条本轮用不上（我们不再手算语速），留档是因为它是这个 API 最容易踩反的地方。

---

## 被否掉的方案（留档，避免下次重走）

| 方案 | 为什么否 |
|---|---|
| 读 VoiceOver 语速再自己算 `rate` | **没有这个 API**，且用户面前有两个独立滑块，不存在单一值 |
| VoiceOver 运行时只发通告、不用合成器 | **2026-08-01 试过，当天回退**：通告在 VoiceOver 忙时会被丢弃，而 SOS 播报不允许丢 |
| 在 App 内自己加一个语速滑块 | 让用户为同一件事设置两次；`prefersAssistiveTechnologySettings` 已经免费拿到正确值。真到了需要独立于 VoiceOver 调速的场景再说 |
| 删掉 `voice` / `rate` 赋值，全交给系统 | VoiceOver **没开**时这两行仍是生效值，删掉等于丢掉中文音色 |

---

## 仍未解决的那一半（需要人耳，不是需要代码）

**VoiceOver 开着时，同一句话同时走通告和合成器，听感上是不是「念两遍」——本轮没有解决，也解决不了。**

本轮之后两条通道的语速和音色会一致，「一快一慢互相拖」那个症状消失；但「同一句听两遍」
（若真的存在）会变成更整齐的两遍。方向上不会更糟 —— 此前是两个不同音色不同语速重叠，
现在最坏情况是同音色回声 —— 但**这是推理，不是实测**。

判定必须由人真机开 VoiceOver 听，见记忆 `audio-correctness-needs-real-ears-not-code-reading`：
调用点顺序参数全对也可能一声不响，音频正确性读代码读不出来。

---

## 来源

- 本机 SDK 头文件 `AVSpeechSynthesis.h:207-210`（**一手，最高优先级**）
- 本机实测 `swift /tmp/pats_check.swift`（出厂值、标度常量）
- [SSAccessibility](https://github.com/splinesoft/SSAccessibility) —— 无公开 API 读语速，及其绕法
- [WWDC 2018 Session 236 “AVSpeechSynthesizer: Making iOS Talk”](https://asciiwwdc.com/2018/sessions/236) —— `rate` 非线性标度；Apple 明说合成器不是 VoiceOver 的替代品
- [Adjust voice and speed for VoiceOver and Speak Screen (Apple Support)](https://support.apple.com/en-us/111798) —— 旁白与朗读内容是两个独立语速设置
- [Change your VoiceOver settings on iPhone (Apple Support)](https://support.apple.com/guide/iphone/change-your-voiceover-settings-iphfa3d32c50/ios) —— 语速可按音色分别设

**核实日期**：2026-08-14
