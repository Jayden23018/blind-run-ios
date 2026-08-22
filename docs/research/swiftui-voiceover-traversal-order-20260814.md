# SwiftUI 里能不能把 VoiceOver 遍历顺序与视觉叠放顺序解耦？

- 日期：2026-08-14
- 触发：UI 用例 `testMockBlindRunnerHomePlacesPrimaryActionBeforeAuxiliaryMapInVoiceOverOrder`
  自 2026-08-07 起恒红（`XCTAssertLessThan failed: ("27") is not less than ("16")`），
  规格 `blind-runner-voice-first-experience` 要求主操作排在辅助地图之前。
- 结论：**做不到。** 在「地图铺满上半屏、内容压在上面」这种叠层结构里，
  SwiftUI 的 VoiceOver 遍历顺序跟随**绘制顺序**，`accessibilitySortPriority` 是空操作。
  装饰性地图改为 `accessibilityHidden(true)`。

> ## ⚠️ 2026-08-22 修正：隐藏的**位置**当时写错了，洞开了 8 天
>
> 上面这句「改为 `accessibilityHidden(true)`」被落成了**在调用方外层**加修饰符
> （`BlindRunnerHomeView.mapBackgroundLayer`）。**那是无效的。**
>
> `MapViewWrapper` 内部有 `.accessibilityElement(children: .ignore)` + `.accessibilityLabel`，
> 它**合成了一个新的无障碍元素**，外层的 `accessibilityHidden` 盖不住。真机实测（真 key 构建）：
>
> ```
> Other  (0,0) 402x200  «地图，显示当前位置和订单地点»   ← 仍排在内容层前面
> ScrollView (0,0) 402x874  #blindRunnerHomeScrollView
> ```
>
> **为什么 08-14 那次没发现**：验证跑的是 UI 测试，而 UI 测试默认 `disableMap: true`
> （`blindRunUITests.swift` 的 `launchApp`），走的是 `MapPlaceholderView` 那条路径 ——
> 占位图确实被藏住了。**生产构建走的是真 key 那条**，从没验过。
> 「在占位图路径上验过」不等于「验过」，这条以后对任何走 `MapViewWrapper` 的改动都成立。
>
> **本文的主结论不变**（遍历顺序 = 绘制顺序；隐藏优于排序）。变的只是落点：
> 隐藏必须发生在**元素被合成的那一层**。现已改为 `MapViewWrapper.isDecorative`，
> 装饰用法根本不合成该元素 —— 藏不住一个不存在的元素。
> 同一个洞在 `BlindOrderStatusView.peerMapSection` 也开着，一并修了。
> 回归钉子：`testRealAMapEnabledSmoke`（真 key 路径，已验红 → 绿）。

## 1. 先修正一个把人带偏的前提：那条断言本身就不可能通过

`app.descendants(matching: .any).allElementsBoundByAccessibilityElement` 是**逐层枚举**的：
同深度的兄弟元素全部排完，才轮到它们的子元素。真机 dump（iPhone 16 Pro / iOS 26）：

```
16 type=48 id=blindRunnerHomeAuxiliaryMap   ← ZStack 直接子层，深度 1
17 type=46 id=blindRunnerHomeScrollView     ← ZStack 直接子层，深度 1
18 type=9  id=gearshape label=设置           ← ZStack 直接子层，深度 1
19 type=9  id=blindRunnerHomeSOSBar
20..23                                       ← 16 的子元素
24..32                                       ← 17 的子元素
27 type=9  id=blindRunnerHomeStartBookingButton label=开始约跑   ← 深度 3
```

「开始约跑」在滚动视图**里面**（深度 3），地图是滚动视图的**兄弟**（深度 1）。
逐层枚举下，任何深度 1 的元素恒排在任何深度 3 的元素之前 ——
**27 vs 16 差的是深度，不是顺序**，再怎么排序也填不平。
把两个不同深度的元素拿来比下标，这个断言从写下那天起就没有可通过的实现。

同深度可比的是「滚动视图 vs 地图」（16 vs 17）。下面的实验都以这一对为准。

## 2. 四种排法，真机实测全部失败

设备 `mac's iPhone`（iPhone 16 Pro），`scripts/device-test.sh`，每次都跑
目标用例 + `AccessibilityAuditTests`（11 条，全程绿）。

| # | 做法 | 地图 vs 内容（同深度下标） | 结果 |
|---|------|--------------------------|------|
| 1 | 三层各挂 `accessibilitySortPriority`（内容 100 / 地图 -1 / 设置 -2），ZStack 无容器 | 16 vs 17 | 地图仍在前 |
| 2 | 换声明顺序（内容先声明），用 `zIndex` 维持视觉叠放 | 16 vs 17 | 地图仍在前；**遍历顺序原样跟着 `zIndex` 走** |
| 3 | 在 ZStack 上加 `accessibilityElement(children: .contain)`，三层都补成容器元素后再排 | 18 vs 19 | 地图仍在前 |
| 4 | 撤掉 ZStack 里的地图层，改成内容层的 `.background(alignment: .top)` | 18 vs 19 | 地图仍在前 |

实验 2 是决定性的：改了声明顺序、只用 `zIndex` 把视觉搬回去，遍历顺序**跟着 `zIndex` 变**。
⇒ 遍历顺序 = 绘制顺序，而不是声明顺序。
实验 3 的 dump 显示 ZStack 容器确实建起来了（元素 16 是容器，子元素 `18 地图 / 19 内容 / 20 设置`），
优先级 -1 / 100 / -2 摆在那儿一个都没生效。

⇒ **`accessibilitySortPriority` 在跨叠放层的场景下是空操作。** 别再往回加。

## 3. 社区口径与我们实测的差异

主流资料都说「把元素放进 stack，再给 stack 加 `accessibilityElement(children: .contain)`，
sortPriority 就生效」，并强调排序**只在同一个无障碍容器内**发生、嵌套 stack 会自成一组
（[Mobile A11y][1]、[Create with Swift][2]、[Rob Whitaker][3]）。

按这个口径我们做了实验 3（容器补齐、三层的优先级都挂在 ZStack 的**直接子层**上），
**仍然无效**。差异点在于：那些例子排的是同一层里的若干 `Text`（等大、不重叠、纯叶子节点），
而我们排的是「一个滚动容器 + 一个铺满的背景层」——**互相重叠且尺寸悬殊**。
在这种结构下 SwiftUI 走的是绘制顺序，社区示例覆盖不到。

顺带修掉一个真实缺陷：`settingsOverlay` 的 `accessibilitySortPriority(-2)`
原本挂在 `HStack` **里面的 Button** 上，只会在 HStack 自己的分组里排序，
对「相对地图/内容的位置」本就没有任何作用 —— 这正是资料里说的「嵌套 stack 自成一组」。
（挂对位置之后依然无效，见实验 3。）

## 4. 采纳的方案

地图层改 `accessibilityHidden(true)`，整棵子树一起隐藏。理由：

- 它是**纯装饰**：`allowsHitTesting(false)`，且不承载任何必要信息 ——
  同样的内容在 `locationSummarySection` 里有文字版。对辅助技术隐藏是装饰性内容的标准处理。
- 效果**优于**原本想要的「排到内容后面」：读屏用户进首页 **0 次**多余划动就够到唯一的主操作，
  而不是「先划过地图再够到」。
- 低视力用户看到的画面**完全不变** —— 隐藏的只是无障碍树里的节点，不是像素。
- 必须整棵子树隐藏：真机上高德的地图视图自己会挂一堆无障碍元素，
  只在最外层挂 label 挡不住它们冒出来。

代价：`blindRunnerHomeAuxiliaryMap` 不再出现在无障碍树里，XCUITest 也就看不见它，
原用例里「恰好挂载一个地图」「地图不可交互」两条断言随之失效。
`homeMapPlaceholder` 那条守卫在 `blindRunUITests.swift:104` 的另一条用例里仍然在跑，覆盖没丢。

被否掉的另外两条路（留档，避免重来）：

- **把地图挪到主操作下方**：绘制顺序 = 阅读顺序，不用跟框架较劲，地图也还能被念出来。
  否决理由是它推翻 `blind-ui-visual-benchmark-20260808.md` 定下的「地图铺满上半屏」视觉设计。
- **改规格，接受划一次**：布局与代码都不动，把要求放宽成「地图最多占主操作前的 1 个停留点」。
  否决理由是盲人用户每次进首页都要多划一下，而这是可以彻底消掉的成本。

## 来源

- [1]: <https://mobilea11y.com/guides/swiftui/swiftui-sort-priority/> — SwiftUI Accessibility: Sort Priority（核实日期 2026-08-14）
- [2]: <https://www.createwithswift.com/preparing-your-app-for-voiceover-customizing-the-sort-priority/> — Preparing your App for VoiceOver: customizing the Sort Priority（核实日期 2026-08-14）
- [3]: <https://medium.com/@r.whitaker/swiftui-accessibility-sort-priority-3c878306ef19> — Rob Whitaker, SwiftUI Accessibility: Sort Priority（核实日期 2026-08-14）
- <https://developer.apple.com/forums/thread/725088> — SwiftUI accessibility inside ZStack + ScrollView（核实日期 2026-08-14）

⚠️ 上面三篇都只给了「同层若干 Text」的例子，**没有一篇覆盖重叠叠放层**。
本文第 2 节的四条真机结论以本仓库实测为准，不以这些文章的表述为准。
