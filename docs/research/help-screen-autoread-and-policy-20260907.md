# 首启帮助页：进入时该不该自动全文朗读？分步列表该不该列？

- 日期：2026-09-07
- 起因：真机实测「进使用帮助页只听到『欢迎使用助盲跑』，不会把三条说明全念完；点『再听一遍』才完整」，
  连带要判这一页的信息架构是否合理。
- 范围：**只查这一段** —— 苹果对「屏幕出现时自动朗读」的口径、以及自动播音频的强制性要求。
  分步列表的排版/减法方向已有 [`blind-voice-booking-ia-20260805.md`](./blind-voice-booking-ia-20260805.md)
  与 [`blind-ui-visual-benchmark-20260808.md`](./blind-ui-visual-benchmark-20260808.md)，未触发复核，直接沿用。

---

## 1. 结论（先说能拿去做决定的部分）

1. **苹果没有「进入屏幕自动朗读全文」这个概念，也没有对应 API 或要求。** 官方口径是
   *光标移进新内容区*，然后由用户自己按节奏浏览。所以「不自动全念」在 VoiceOver 通道下
   **不是缺陷，是正常行为**。
2. **但本项目有第二条通道**：不开读屏的低视力 / 全盲用户靠 App 自己的 `AVSpeechSynthesizer`。
   这条通道上「一个字都没有」才是真缺陷。⇒ 判据不是「要不要自动念」，而是
   **「VoiceOver 开着时不要抢，VoiceOver 没开时必须念」**。
3. **自动播报超过 3 秒就必须给停止手段**（WCAG 2.2 SC 1.4.2，**Level A** —— 最低一档）。
   现状这一页自动播 ~40–60 秒且没有任何「停止播报」入口，离开页面也不停。这是本轮唯一
   够得上「硬性条款」的一条。
4. **「第一、第二、第三」保留。** 没有任何政策要求或禁止它；苹果的「简洁」条款针对的是
   **控件标签**，不是正文。而线性播报里它是唯一的位置线索（听的人没有视觉分段）。
5. **底部常驻栏遮住滚动内容**这件事有对口条款：WCAG 2.2 SC 2.4.11（AA）。见 §4。

---

## 2. 一手材料（自行抓取原文，非搜索转述）

### 2.1 Apple — App Store Connect《VoiceOver evaluation criteria》

抓取方式：`curl` 直连 `developer.apple.com`，2026-09-07 核实，HTTP 200。
这是 Accessibility Nutrition Labels 体系下**判定一个 App 能不能标称「支持 VoiceOver」**的官方标准。

逐字摘录（与本议题相关的四条）：

> Labels should be concise, so that the interface isn't tedious for a user to navigate and understand quickly.

> Temporary status banners and important in-app alerts should be conveyed to VoiceOver users in a timely but non-disruptive manner, often done so with an AccessibilityNotification.

> When the screen changes or a modal dialog appears, the VoiceOver cursor should move logically into the new content area. VoiceOver users shouldn't be able to move into invisible, offscreen, or background content.

> VoiceOver users should be able to navigate in page order, or move directly to a part of the screen using features like the VoiceOver rotors.

**读法**：整份标准里没有一句提到「进入页面自动朗读全部内容」。它反复要求的是
*可导航、非侵入、光标落到该落的地方*。「timely but **non-disruptive**」这半句是关键 ——
一段 40 秒、不能中断、盖住 VoiceOver 自身播报的自动朗读，正好落在 disruptive 那一侧。

来源：<https://developer.apple.com/help/app-store-connect/manage-app-accessibility/voiceover-evaluation-criteria/> ｜ 置信度 **[高]**（Apple 官方，一手抓取）

### 2.2 W3C — WCAG 2.2 SC 1.4.2 Audio Control（Level A）

抓取方式：`curl` 直连 `w3.org/TR/WCAG22/`，2026-09-07 核实，HTTP 200。逐字：

> If any audio on a web page plays automatically for more than 3 seconds, either a mechanism is available to pause or stop the audio, or a mechanism is available to control audio volume independently from the overall system volume level.

同条附注（同样逐字）：

> Since any content that does not meet this success criterion can interfere with a user's ability to use the whole page, all content on the web page (whether or not it is used to meet other success criteria) must meet this success criterion.

**对本项目的含义**：条款写的是 web page，移动 App 走的是 WCAG2Mobile / EN 301 549 的映射，
但**这一条的映射没有争议**（自动播音频 + 无停止手段）。它是 Level A，也就是说
只要 App 声称做无障碍，这条就是地板不是天花板。

⚠️ 注意它是「pause **or** stop」二选一，且**系统音量键不算**——必须是应用内独立于系统音量的机制。
现状这一页：`SpeechService.stop()` 存在（`blindRun/Voice/SpeechService.swift:150`）但**这一页没有任何入口调它**。

来源：<https://www.w3.org/TR/WCAG22/#audio-control> ｜ 置信度 **[高]**（W3C 规范正文，一手抓取）

### 2.3 W3C — WCAG 2.2 SC 2.4.11 Focus Not Obscured (Minimum)（Level AA）

逐字：

> When a user interface component receives keyboard focus, the component is not entirely hidden due to author-created content.

**对本项目的含义**：这是 2.2 新增条款，直接针对**粘性页脚遮住聚焦控件**这个模式。
AA 档只要求「不被**完全**遮住」，AAA 的 2.4.12 才要求一点都不遮。
盲人端订单状态页的底部常驻栏（`safeAreaInset(edge: .bottom)`）在 AA 档上是过的
（滚动内容不会被完全吞掉，`safeAreaInset` 会自动留出底部 inset），
**但半透明材质导致的文字叠影不在这条管辖内** —— 那是对比度/可读性问题，属另一条线（见 §4）。

来源：<https://www.w3.org/TR/WCAG22/#focus-not-obscured-minimum> ｜ 置信度 **[高]**

---

## 3. 转述级材料（未抓原文，仅作旁证，不作决策依据）

经 `WebSearch` 转述、**未自行抓原文**，按 [中] 对待：

- `.announcement` 通知在导航发生时**会被 VoiceOver 打断/丢弃**，社区一致建议改用
  `.screenChanged` 并传字符串或目标元素。这条与我们观察到的现象方向一致，
  但它**不是**本次缺陷的根因（根因是本仓库自己的播报竞态，见下方「与代码的对照」），
  所以没有继续追一手来源。
- Apple 示例代码对播报做节流（「否则会很吵」）。方向性参考，无条款效力。

---

## 4. 与本仓库代码的对照（这部分不是调研结论，是核对结果，写在这里是为了让上面的条款可执行）

> 📌 **本节所有行号都是改动**前**的，锚在 `origin/main @ 9c82c01`。** 修复分支上它们必然对不上 ——
> 这是描述缺陷的文档，引的就该是缺陷还在的那一版。核对请用
> `git show 9c82c01:<路径>`，别拿当前工作区去对（已经有人这么对过一次，误判成行号漂移）。

| 条款 | 现状 | 判定 |
|---|---|---|
| Apple「non-disruptive」 | 进入页面时 `UIAccessibility.post(.announcement)` 与 `AVSpeechSynthesizer` **同时**播同一段全文（`SpeechService.swift:39-50`，代码注释自认「听感上可能是念两遍……仍未在真机上确认过」） | ⚠️ 存疑，**要真机人耳验**，不靠读代码拍板 |
| Apple「光标移进新内容区」 | 走的是 `NavigationStack` push，系统默认行为，未额外干预 | ✅ 合规 |
| WCAG 1.4.2（A） | 自动播 ~40–60 秒；页面上只有「再听一遍」「知道了」，**没有停止入口**；`dismiss()` 也不停 | ❌ **不合规** |
| WCAG 2.4.11（AA） | 底部常驻栏用 `safeAreaInset`，滚动内容有自动 inset | ✅ 合规（叠影是另一条线） |
| 「第一/第二/第三」 | 线性脚本里是唯一位置线索；VoiceOver 下每条自成一个焦点元素 | ✅ 保留，无条款反对 |

**真正让用户听不到全文的根因不在上面任何一条**，是本仓库自己的播报竞态：
首页 `.task` 先 push 引导页、再 `await loadActiveOrder()`；加载回来后
`speakCurrentStatus()`（`BlindRunnerHomeView.swift:220 → 272`）播「欢迎来到助盲跑……」，
而 `SpeechService.speak` 的第一件事是 `synthesizer.stopSpeaking(at: .immediate)`
（`SpeechService.swift:47`）—— 把引导页刚念了一两秒的说明当场切断。
两句都以「欢迎…助盲跑」开头，所以听起来像「只念了标题就停了」。
这条**不是政策问题，是竞态缺陷**，修法与本报告无关。

---

## 5. 被否掉的方案（留档，理由比结论值钱）

- ⛔ **「进页面就把全文自动念完」当成无障碍最佳实践**。查下来苹果既没要求也没提供 API，
  而 WCAG 1.4.2 反过来给它加了 Level A 的附加义务。方向应改成
  「VoiceOver 在跑就别抢，VoiceOver 没开才自己念」。
- ⛔ **删掉「第一、第二、第三」求简洁**。苹果那句 concise 管的是控件标签，
  引到正文上是错引；线性播报里删掉序号等于删掉唯一的进度线索。
- ⛔ **用 `.screenChanged` 替 `.announcement` 来「修」这个 bug**。它治的是另一种病
  （通告被导航打断）；本例的实际根因是我们自己的 `stopSpeaking`，换通知类型不会好。

---

## 6. 未解决 / 需真机验的

1. VoiceOver 开着时，同一句同时走通告与合成器**到底是不是念两遍** ——
   `blind-voice-booking-ia-20260805` 与 `tts-rate-follows-voiceover-20260814` 都挂着这条，本轮仍未解决。
   只能真机开 VoiceOver 人耳验（记忆 `audio-correctness-needs-real-ears-not-code-reading`）。
2. 「两根手指双击」在**订单状态页**上是否真的落到系统默认动作（播放音乐）。
   代码事实确定：全仓 `.accessibilityAction(.magicTap)` 只有两处
   （`BlindRunnerHomeView.swift:487`、`BlindBookingView.swift:1047`），**订单状态页没有**；
   但「响应链是否会走到 NavigationStack 根视图」需真机验一次才能下断言。
3. 移动 App 上 WCAG 1.4.2 的执法口径（EN 301 549 / WCAG2Mobile 的映射细节）未查，
   本轮按「条款语义直接适用」处理。

---

## 来源清单

| 来源 | 抓取方式 | 核实日期 | 置信度 |
|---|---|---|---|
| [Apple — VoiceOver evaluation criteria](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/voiceover-evaluation-criteria/) | `curl` 直连，HTTP 200 | 2026-09-07 | 高（一手） |
| [W3C — WCAG 2.2 SC 1.4.2 Audio Control](https://www.w3.org/TR/WCAG22/#audio-control) | `curl` 直连，HTTP 200 | 2026-09-07 | 高（一手） |
| [W3C — WCAG 2.2 SC 2.4.11 Focus Not Obscured (Minimum)](https://www.w3.org/TR/WCAG22/#focus-not-obscured-minimum) | `curl` 直连，HTTP 200 | 2026-09-07 | 高（一手） |
| `.announcement` 被导航打断 | WebSearch 转述，未抓原文 | 2026-09-07 | 中 |

抓取备注：`r.jina.ai` 本机 `curl` 报 `LibreSSL SSL_connect: SSL_ERROR_SYSCALL`（443 直接失败），
本轮改走 `curl` 直连目标站 + 内联 python 剥标签，两站均 200。
`developer.apple.com` 的正文在 `<main>` 内且前面有约 10k 字符的侧边导航，
按 `<main>` 截取后再定位正文关键词才取得到 —— 直接取前 N 个字符只会拿到导航目录。
