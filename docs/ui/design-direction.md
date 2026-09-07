# Design Direction

**这份文档回答的是「它该长什么样、为什么」。**
「这页要有什么」在 [`ui-handoff-ios.md`](./ui-handoff-ios.md)，「改完要检查什么」在
[`ui-review-checklist.md`](./ui-review-checklist.md)，三份不重叠。

**怎么用**：改任何界面之前，先照官方两遍工作法走第一遍 ——
出一个 design plan（色/字/布局/原则），**对着本文件自审「这是不是我对任何同类页面都会产出的默认值」**，
是就改掉并说明改了什么、为什么；确认过才开始写代码。
依据见 [`docs/research/ai-ui-design-workflow-for-swiftui-20260907.md`](../research/ai-ui-design-workflow-for-swiftui-20260907.md) §3.2。

---

## 1. 方向

| 端 | 性格 | 一句话 |
|---|---|---|
| 盲人端 | **公共服务的克制可靠** | 像市政服务窗口，不像消费级 App。可预期 > 惊喜 |
| 志愿者端 | **运动产品的明快**，但**按场景分档**（见 §6） | 激励与成长可以有节奏感；安全相关一律退回克制 |

**盲人端克制的理由不是「反正看不见」** —— `VisionLevel.lowVision`
（[`ProfileModels.swift:406`](../../blindRun/Core/Models/ProfileModels.swift)）是数据模型里的一等公民，
低视力用户**看得见**，只是看不清。视觉层的唯一服务对象就是他们，而他们要的正是克制：
「明快」的典型手段（高饱和强调色、彩色状态点、渐变）与「可读」直接冲突 ——
`AppColors.swift:8-11` 的实测里，`systemOrange` 压白底只有 **2.20:1**、`systemGreen` **2.22:1**，
而正文阈值是 4.5:1。

⚠️ 所以后续每加一个装饰色都要过对比度这一关。**按「反正看不见」那个理由推导，会得出相反的结论。**

---

## 2. Color —— 不新增，直接用 `AppColors`

色板即 [`blindRun/Core/DesignSystem/AppColors.swift`](../../blindRun/Core/DesignSystem/AppColors.swift)，
**本文件不定义第二套取值**（两个源必然漂移）。

- 语义色 5 个：`primary` / `destructive` / `warning` / `success` / `textSecondary`，各带亮暗两套。
- 亮色模式**不用 iOS 系统语义色**（上面那组实测数字就是理由），暗色模式用系统色。
- 改任何取值先跑 **`LowVisionChannelTests`** —— `testEverySemanticColorClearsTheBodyTextContrastThreshold…`
  按 WCAG 相对亮度公式在亮暗两套外观上重算，`testTheContrastFormulaActuallyRejectsTheOldSystemColors`
  反过来验证这套公式真的会拒（防止断言恒真）。
  ⚠️ `AppColors.swift:17` 的注释此前写的是 `AppColorContrastTests`，**全仓不存在这个类型**，
  照它去跑只会「找不到就跳过」—— 已在本次一并改正。
- 系统「增强对比度」开关打开时，`HighContrastText` 会把次要色并到 `textPrimary`（换 AAA 的 7:1），
  **不要另起一套增强色板**。

**新增强调色的门槛**：先证明现有 5 个语义色都表达不了这个含义，再跑对比度，再改。
装饰性色彩（纯为了好看的）**一律不加**。

---

## 3. Type —— 用 `AppFonts`，且永不封顶

- 5 个语义函数：`largeTitle` / `title` / `body` / `caption` / `primaryButton`（`AppColors.swift:91-107`）。
- **不封顶 Dynamic Type**。AX4 / AX5 正是低视力用户实际会设的档位（body 在 AX5 是 53pt ≈ 默认的 310%），
  封在 AX3 等于把最后两级从目标用户手里拿走。理由与实测见
  [`dynamic-type-scale-20260812.md`](../research/dynamic-type-scale-20260812.md)。
- **不用 `.font(.caption2)`**，`.caption` 也要谨慎（`swiftui-pro/references/design.md:32`）。
- 正文列宽上限 `BlindLayout.readableContentWidth = 700`（每行 45–75 字符）—— 放大字号后横扫整行会串行。

---

## 4. Layout

六条可对着像素核对的规则在
[`blind-ui-visual-benchmark-20260808.md`](../research/blind-ui-visual-benchmark-20260808.md) §1，
**本文件不复述**。只记它们的共同前提：

> **一屏一个主任务，主动作是一整块面积而不是一个「按钮」。**

配套的既有实现（用它们，不要重写）：
- `PrimaryButton`：全宽、`minHeight: 64`、`cornerRadius(12)`。
- `BlindLayout.compactDecorativeMapHeight = 96`：矮窗口（iPhone 横屏）下装饰地图的高度上限。
- 次级操作**整行铺满竖直堆叠，绝不并排**（对标产品无一例外并排）。
- 圆形大按钮是错方向：同外接尺寸下圆形只有 π/4 ≈ 78.5% 的可点面积。

---

## 5. Principles

1. **视觉语言全 App 统一且克制**，色板即 `AppColors`，不新增强调色。
2. **两端差异只走三个轴：信息密度、层级丰富度、文案语气。** 不走两套色、不分叉共享组件。
3. **盲人端的「温度」由播报措辞与触觉反馈承载，不由颜色承载。**
   这条已有测试钉住而不只是主张：`LowVisionChannelTests.testEveryOrderStatusMakesAnExplicitHapticDecision`
   要求每个订单状态都**显式**决定用哪种触感（不许漏），
   `testProgressAndSetbackDoNotShareTheSameHaptic` 要求「进展」与「挫折」触感可区分 ——
   加新状态时编译器与测试会逼你做这个决定。
4. **安全相关界面在两端都用最克制的一档**，且与激励类界面在视觉上明确可区分。

> 第 2 条的代价说明：两端做两套视觉语言，意味着 `AppColors` 与
> `HighContrastText` / `PrimaryButton` / `ReadableContentColumn` 三个共享组件要分叉 ——
> 那三个组件是目前最值钱的设计资产，每一条注释里都压着一次实测。分叉的收益是「看起来不一样」，
> 代价是每条无障碍保证都要维护两遍。**不划算。**

---

## 6. 场景分档（志愿者端尤其重要）

| 场景 | 档位 | 具体表现 |
|---|---|---|
| 激励 / 成长 / 徽章 / 历史轨迹 | **明快** | 信息密度可高、层级可丰富、可有进度动效 |
| 派单 / 接单 / 通话磨合 | 中性 | 按 `ui-handoff-ios.md` 的页面规格 |
| **服务进行中 / SOS / 位置上报 / 距离预警** | **最克制** | 一个身份 + 一个巨大动作，无装饰、无非用户触发动效 |

**运动产品的语言用在 SOS 界面上是灾难** —— 那一屏的目标是「按下去不出错」，不是「让人有成就感」。
SOS 二次确认文案是逐字锁定的（`AGENTS.md` §6），那种严肃度与「今天又解锁一枚徽章」
放进同一套视觉语言里会互相削弱。

---

## 7. 反指纹清单（iOS 版，逐条点名）

外面流传的那份 AI 指纹清单（Inter / Roboto、紫色渐变、玻璃拟态）是 **Web 语境，对本仓库无效**：
iOS 默认排版是 San Francisco；玻璃拟态在 iOS 26 是 Apple 官方方向，与 Web 的结论相反。
以下是本仓库自己的清单 —— **写「好看一点」没用，要逐条点名**（依据：调研报告 §3.3 的 B 派论据）。

- ❌ 清一色 `.blue` 做强调色（SwiftUI 默认值，等于没做选择）
- ❌ 所有卡片同一个 `cornerRadius` 而无视层级差异
- ❌ 用 SF Symbols 堆装饰 —— 每个图标要么有 `accessibilityLabel`，要么 `accessibilityHidden(true)`
- ❌ `.font(.caption2)`；`.caption` 承载正文
- ❌ 盲人端的非用户触发动效（页面出现时的淡入上滑、常驻的呼吸/闪烁状态点）
- ❌ 用颜色作为唯一的状态区分手段（色觉障碍 + VoiceOver 都拿不到）
- ❌ 把「订单进行中」这类状态做成彩色圆点 + 小字，而不是一句可播报的话
- ❌ 三列指标网格塞进窄屏（AX5 档必然截断 —— 已有实测：志愿者端指标格截断成「…」）
- ❌ 为了「看起来饱满」增加的说明性小字（每多一行，VoiceOver 用户就多划一次）

---

## 8. 写作原则

界面里的字是设计内容，不是装饰。以下五条取自 Anthropic `frontend-design` skill 的
`## More on writing in design`，**对本仓库比它的视觉部分更重要** —— 盲人端的「界面」相当程度上就是
文案与 TTS 播报。

1. **按用户理解的方式命名**，不按系统实现命名。用户管理的是「紧急联系人」，不是 `EmergencyContactResponse`。
2. **动词用主动语态，按钮说清按下去会发生什么**：「确认下单」而不是「提交」。
3. **一个动作在整个流程里保持同名** —— 按钮叫「确认出发」，后续播报就说「已确认出发」。
   这一条对 TTS 尤其硬：用户听到的词和他按的词不一致时，无法确认操作是否生效。
4. **错误不道歉，也绝不含糊**：说清发生了什么、怎么办。不写「哎呀，出错了」。
5. **空状态是行动邀请**，不是情绪表达。

**本仓库叠加的红线**（`AGENTS.md` §6，违反是事故不是风格问题）：
- 永远不得宣称短信已发出 / 已送达 / 家属已被通知；
- SOS 降级为本地拨号时，必须说清「App 不会代你发送求助」；
- 状态词必须与 `AGENTS.md` §5 的状态机一致，不得自造同义词。

---

## 9. 视觉参考素材（注意：不在仓库里）

`docs/ui/reference-screenshots/`（12 个同类产品的截图）被 [`.gitignore:81`](../../.gitignore) 显式忽略，
**从未提交过任何分支** —— 它只存在于最初做竞品调研那台机器的工作区。

⇒ 「从 reference-screenshots 挑一张贴进 prompt」**不能作为团队流程**写进来，别人 clone 下来没有这批图。
可复用的锚定物只有两个，都在仓库里：
- [`blind-ui-visual-benchmark-20260808.md`](../research/blind-ui-visual-benchmark-20260808.md) 的六条规则（文字形式，人人可读）；
- `docs/ui/legacy-screenshots/`（已提交，23 个文件），但它是**旧 Flutter 版**，
  按 `ui-reference-audit.md` §6 的裁决使用 —— 那里逐条写了哪些不适合新版。

要把竞品图变成团队资产，得先决定是否解除 gitignore（会给仓库增加约 112 个二进制文件，且涉及第三方
App 截图的使用边界）。**在做出这个决定之前，本文件不假设任何人手上有这批图。**
