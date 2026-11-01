# 苹果式「简约而高级」怎么落到无障碍 App 上（2026-11-01）

问题：苹果式的简约高级到底由什么构成？跑步之外的成熟 App 怎么排按钮和内容？这些做法哪些能用在助盲跑上？

本篇只补缺口。下面几份已有结论这轮没有重查：

- `blind-ui-visual-benchmark-20260808.md`：盲人端主动作的面积与堆叠规则。
- `copy-tone-benchmark-20261028.md`：文案口吻。
- `ios-design-repos-and-list-row-actions-20261030.md`：列表行用小箭头进详情页。
- `blind-runner-redesign-references-20261007.md`：ADA 无障碍获奖产品的多通道做法。

> ⚠️ 2026-11-01 订正：据此做的静音版方案已被负责人否决。§3 的 App 是按视觉风格挑的，多数不是助盲跑对应页面的同功能界面（Cash App 金额键盘对语音预约、Things 待办对求助中心、Apple Sports 比分对订单页）。**§3 不能当逐屏参考。** §1、§2、§4 的官方原文和对比度数字仍然有效。以后选参考图先按「同一个功能」筛，再看风格。

## 0. 结论

1. **「高级」主要来自减法和层级，不是来自特效。** Apple 2026 年的品牌课程把 App 分成两层：导航和操作用系统标准件，品牌只放在内容层。颜色要少，且每种颜色都要有含义。
2. **玻璃材质不是这个项目的抓手。** 低视力用户的风险已有实测报告，我们的标签栏也有不用半透明的实测理由。结论是内容层不用玻璃，系统自带的部分不主动关闭也不加强。
3. **苹果的白卡灰底对低视力用户几乎没有边界。** 白卡压页面底只有 1.11:1。可以用这个版式，但卡片不能承担信息。分组要靠标题、留白、文字层级来表达。
4. **最值得照抄的不是某一屏，是三条纪律**：一屏一个实心主按钮；一个状态一句大字；其余内容退到列表。

## 1. 一手材料

| 材料 | 取得方式 | 日期 |
|---|---|---|
| Apple HIG：Buttons、Layout、Typography、Color、Designing for iOS、Materials、Motion | `developer.apple.com/tutorials/data/design/human-interface-guidelines/<页面>.json`。HIG 网页是动态加载，这个 JSON 才是原文 | 2026-11-01 |
| WWDC26《Communicate your brand identity on iOS》逐字稿 | <https://developer.apple.com/videos/play/wwdc2026/251/> | 2026-11-01 |
| WWDC25《Meet Liquid Glass》搜索摘要 | <https://developer.apple.com/videos/play/wwdc2025/219/> | 2026-11-01 |
| 15 个 App 的 App Store 官方截图 | iTunes Lookup，脚本 `scripts/fetch-reference-screenshots.mjs` | 2026-11-01 |
| WCAG 1.4.11 | <https://www.w3.org/WAI/WCAG21/Understanding/non-text-contrast> | 2026-11-01 |
| Liquid Glass 可读性审计与争议 | Infinum 审计、Apple 开发者论坛 thread 811219 | 2026-11-01 |

截图重抓命令（目录被 gitignore，`node` 跑一次即可）：

```bash
node scripts/fetch-reference-screenshots.mjs
```

⚠️ App Store 截图是营销图，一屏里常带拼接和外框。它能证明版式和按钮样式，不能证明完整流程。

## 2. Apple 自己怎么说

逐字引用只留一条，其余是转述。

### 2.1 分层

- WWDC26 把 App 分成 UI 层和内容层。UI 层是导航和操作，内容层才是表达品牌的地方。
- UI 层优先用标准组件。自定义的功能性组件通常不会加强品牌，反而可能让 App 显得不原生或过时。
- 定制组件要花在最影响体验或最能突出内容的地方。其余部分要审查，能换成标准件就换。
- 上下文菜单是常被忽略的标准件，适合放整屏相关的次要操作。

### 2.2 颜色

- 颜色应表达含义：层级、分组、可交互。颜色过多会让界面显得压迫。
- 色调色主要用在主操作、未读标记、新建操作、选中态。
- 课程总结：克制使用颜色，「sparingly and with intention」。
- HIG Color：同一种颜色不要表示不同含义。
- HIG Color：要强调主操作时，把颜色放在背景上，不放在符号或文字上。
- HIG Color：颜色要在浅色、深色、增强对比度三种环境下都成立。

### 2.3 按钮

- HIG Buttons：一屏里最可能的操作用醒目样式。
- HIG Buttons：用样式区分主次，不用尺寸。同尺寸按钮表示它们是一组选择。
- HIG Buttons：危险操作不要用主按钮角色，因为人们可能不读就按。
- HIG Buttons：内容层已经很鲜艳时，按钮标签优先用单色。
- Designing for iOS：限制屏幕上的控件数量，把次要内容放到一步可达的位置。

### 2.4 字体

- HIG Typography：用字重、字号、颜色建立层级，放大字号后层级要保持。
- HIG Typography：字体种类要少。优先用系统文本样式，它自动支持 Dynamic Type。
- HIG Typography：避免 Ultralight、Thin、Light 字重。
- WWDC26：Gentler Streak 全部用系统字体，靠字宽和 SF Rounded 做出个性。

### 2.5 版式

- HIG Layout：对齐和缩进表达层级，渐进展示让版面更干净。
- HIG Layout：控件和内容要有区别。不要在控件下面垫实色或半透明底，改用滚动边缘效果。
- HIG Designing for iOS：常用控件放在屏幕中下部更容易够到。

### 2.6 动效

- WWDC26：动效用来强调层级。掉帧和迟缓加载会直接损害观感。
- 本仓库盲人端已有「无非用户触发动效」的规则，继续有效。

## 3. 15 款 App 看到的共同做法

| App | 可借 | 不借 |
|---|---|---|
| Apple 健康 | 大标题 + 分组白卡；每张卡只有一个结论（一句话或一个数字）；卡片标题小而带类别色 | 卡片只靠极浅底色分界；图表细线 |
| Apple 健身 | 状态概览分块；主数字巨大，标签很小；黑底 + 一个强调色 | 荧光绿强调色压小字；三列小指标 |
| Apple Sports | 比分是整屏唯一的巨字；一屏只有一种大数字节奏；列表行极规整 | 按球队切换满屏背景色 |
| Uber / Uber Driver | 一屏一个黑色实心按钮；「3 min away」这种一句状态大字；卡片压在地图上 | 小字密集的费用行；纯黑按钮在暗色下要反色 |
| Lyft | 选中卡片用描边，不用填色 | 紫色品牌渐变 |
| Flighty | 用状态颜色只标一个小胶囊，主体仍是黑白信息 | 深色渐变营销感、信息密度过高 |
| Runna | 跑步中一行巨字说「现在跑什么」，下一段在小字 | 荧光绿小字 |
| Gentler Streak | 系统字体 + 插画就有品牌感；总结页一句结论 + 下面几个数字 | 卡通角色不适合「公共服务」气质 |
| Oko（ADA 无障碍获奖） | 整块大色带只表达一个状态；留白大 | 地图小字 |
| Tide Guide（ADA 2026 视觉奖） | 图表当内容主角 | 深蓝满屏 + 小字，低视力不友好 |
| Citymapper | 大数字时间 + 小单位 | 高饱和绿与卡通风 |
| Things | 留白、对齐、统一列表行，是「安静」的最好例子 | 12pt 上下的灰色副文 |
| Cash App | 超大金额 + 一个黑色主按钮；同屏两个操作用同尺寸黑胶囊 | 胶囊按钮偏矮（远低于 64pt） |
| Airbnb | 行程页：一张主卡 + 时间线列表；选择页用整张描边卡 | 图片驱动，我们没有这类内容 |

共同点有五条：

1. 一屏只有一个视觉重心，通常是一句状态或一个数字。
2. 主按钮是实心单色，次要操作明显更轻。全屏很少看到第二个实心按钮。
3. 颜色面积小。大面积只有黑、白、灰，颜色只出现在状态、选中、主操作上。
4. 列表行规整，行高、左缘、箭头全部对齐。
5. 主数字和标签差距很大，一般 3 倍以上。

反例也一致：说明性小字、渐变、多种圆角、多种实心按钮，会让界面立刻显得便宜。

## 4. 无障碍约束下的修正

| 苹果式做法 | 风险 | 本项目的处理 |
|---|---|---|
| 白卡压浅灰底 | `#FFFFFF` 压 `#F2F3F6` 只有 1.11:1，低视力和强光下看不出卡片 | 版式可用。卡片不能是唯一线索，分组靠标题和留白。需要点击的卡片保留箭头或描边 |
| 细分隔线 | `#EEF0F4` 压白底 1.14:1 | 分隔线只当装饰，不表达可点击 |
| 44pt 控件 | 盲人端要 64pt | 比例照学，尺寸不学 |
| 小字副标题 | Dynamic Type 与低视力 | 用系统文本样式，副文不低于 `.subheadline`，不封顶 |
| Liquid Glass | Infinum 审计报告局部低至 1.5:1。这是单一公司审计，只作方向参考 | 内容层不用玻璃 |
| 纯黑主按钮 | 暗色模式下压黑底看不见 | 用语义色，暗色反成白底黑字或保留黄色 |
| 颜色面积变小 | 盲人端头卡状态色是负责人 10-07 定的冗余线索 | 不取消。只收敛同屏其他颜色 |

本轮算出的对比度（WCAG 相对亮度公式）：

| 组合 | 对比度 | 说明 |
|---|---|---|
| 白卡 / 页面底 `#F2F3F6` | 1.11:1 | 低于 3:1 |
| 暗色卡 `#1C1C1E` / 黑 | 1.23:1 | 低于 3:1 |
| 黄色主按钮 `#F6C343` / 白 | 1.64:1 | 按钮外形靠文字补足 |
| 黄色主按钮 / 页面底 | 1.48:1 | 同上 |
| 黄色主按钮描边 `#D9A21E` / 白 | 2.30:1 | 低于 3:1 |
| 深字 `#111A2E` / 黄色主按钮 | 10.57:1 | 文字很清楚 |
| 主文字色 `#151A26` / 页面底 | 15.67:1 | 深色按钮外形清楚 |
| 黄色主按钮 / 黑底 | 12.81:1 | 暗色下外形清楚 |

WCAG 1.4.11 只要求识别控件所必需的视觉信息达到 3:1。按钮靠文字就能识别时，黄色外形不算违规。这里记录的是低视力和强光下的观感风险，不是合规结论。

## 5. 否决的方向

- **照抄 Liquid Glass**：工程部署目标 iOS 16，自定义玻璃要写 `#available` 分支。可读性风险落在我们最脆弱的用户上。
- **黑白极简（Uber 式）替换全部状态色**：与负责人 10-07、10-13 的决定冲突，也丢掉低视力的颜色线索。
- **自定义字体**：破坏 Dynamic Type，且没有收益。
- **卡通品牌角色**：与盲人端「公共服务的克制可靠」不符。

## 6. 没查到

- 没有查到 Uber Base 官方按钮层级文档。「一屏一个黑色按钮」只来自截图观察和第三方分析。
- 没有查到户外强光下对比度阈值的权威来源。
- 没有查到 Liquid Glass 的同行评审对比度研究。
- App Store 截图没有覆盖 Apple 健身 iOS 26 的跑后总结页。

## 7. 来源

- [Communicate your brand identity on iOS - WWDC26](https://developer.apple.com/videos/play/wwdc2026/251/)
- [Meet Liquid Glass - WWDC25](https://developer.apple.com/videos/play/wwdc2025/219/)
- [Apple HIG 更新记录](https://developer.apple.com/design/whats-new/)
- [Apple HIG: Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons)
- [Apple HIG: Layout](https://developer.apple.com/design/human-interface-guidelines/layout)
- [Apple HIG: Typography](https://developer.apple.com/design/human-interface-guidelines/typography)
- [Apple HIG: Color](https://developer.apple.com/design/human-interface-guidelines/color)
- [WCAG Understanding 1.4.11](https://www.w3.org/WAI/WCAG21/Understanding/non-text-contrast)
- [Infinum: iOS 26 Liquid Glass accessibility](https://infinum.com/blog/apples-ios-26-liquid-glass-sleek-shiny-and-questionably-accessible/)
- [Apple Developer Forums thread 811219](https://developer.apple.com/forums/thread/811219)
- [2026 Apple Design Awards](https://www.apple.com/newsroom/2026/06/apple-reveals-winners-of-the-2026-apple-design-awards/)
