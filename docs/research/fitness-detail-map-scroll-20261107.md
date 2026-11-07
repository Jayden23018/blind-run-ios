# 跑后详情页照健身：地图固定在背后、往上滑渐渐模糊（#823 第二轮）

日期：2026-11-07。触发：负责人装机反馈第 5 条（原话见 `docs/ui/mockups/run-record/DECISIONS.md` 2026-11-07 第二轮）。

## 问题

1. 苹果「健身」体能训练详情页的地图和内容是怎么叠的、滑动时地图怎么变？
2. iOS 16 部署目标下，SwiftUI 怎么做「固定背景 + 按滚动距离加模糊 / 变暗」？
3. 高德 `MAMapView` 放在模糊层下面，耗电会不会成问题？

## 结论

### 1. 健身的实际表现（一手材料：负责人 iPhone 截图）

只有负责人 2026-11-07 在 iOS 26/27 上截的两张图（`~/Documents/aidrun-design-archive/2026-11-07-run-record-fitness/ref-apple/`，含真实地点，**不进仓库**）：

- 页顶：地图从屏幕顶铺到大约 60% 高，返回键与右上两个圆钮浮在地图上。地点、标题、距离、日期压在地图下沿，下面垫着一段渐变。「体能训练详细信息」卡片从地图下沿开始。
- 滑到中段：卡片已经盖到状态栏下面，**地图完全看不见**，页面底色是纯色。卡片顶上紧贴状态栏的一条有系统的边缘模糊（iOS 26 的 scroll edge effect）。
- 公开网页**没找到**描述这一页滚动效果的文章或视频（中英文各搜两轮，结果都是第三方路线 App）。滑动过程中「先模糊、再消失」的细节来自负责人的口述：「你滑动卡片，就会有一个渐渐，就变得模糊的过程……滑上去慢慢的就把这个地图显现」。

⇒ 结构定为：**地图固定在页面背后，不随内容滚动；内容（头部 + 卡片）在它上面滚；滚动距离驱动一层盖在地图上的遮罩**。

### 2. iOS 16 的做法

- 读滚动距离：内容最顶上放一个透明块，用 `GeometryReader` 取它在滚动视图命名坐标系里的 `minY`，经 `PreferenceKey` 传出去。iOS 16 没有 `onScrollGeometryChange`（iOS 18），这是通行写法。来源：Daniel Saidi《Adding a sticky header to a SwiftUI ScrollView》（2023-02-09，[原文](https://danielsaidi.com/blog/2023/02/09/adding-a-sticky-header-to-a-swiftui-scroll-view)，本次已读），同作者的 offset tracking 一篇同法。
- 别让整页每帧重算：滚动距离放在一个 `ObservableObject` 里，用 `@State` 持有（不订阅），只有遮罩那一个小视图 `@ObservedObject` 它。
- 模糊：遮罩里放 `.ultraThinMaterial`，按进度调透明度；再叠一层页底色，按进度从透明到不透明。**不对地图视图本身用 `.blur`**。
- 「减少透明度」打开（`accessibilityReduceTransparency`）时不用材质，只变暗。
- iOS 26 的 `safeAreaBar` / `scrollEdgeEffectStyle` 能做顶边模糊，但要 iOS 26（[开发者论坛 840840](https://developer.apple.com/forums/thread/840840)），本仓库部署目标 iOS 16，不用。

### 3. 耗电

- 本仓库所有高德地图都设了 `maxRenderFrame = 10` 和 `isAllowDecreaseFrame`（`AMapContainer.makeUIView`），跑后详情的地图不跟手、不动画，静止时基本不重绘。
- 材质层由系统合成，模糊的是已经画好的画面；`.blur` 修饰符会把地图整层离屏渲染，而且地图每次重绘都要重算，所以不用。
- 未做：真机耗电测量（负责人 11-05 定不跑真机测试）。装机目视时留意滑动是否掉帧。

## 采用的参数（起始值，真机看了再调）

设 D = 地图高度 − 安全区顶（内容顶从地图下沿滑到导航栏下沿的距离），进度 p = 已滑距离 / D，截到 0…1：

- 模糊层透明度 = min(2p, 1)：滑到一半已完全模糊。
- 页底色透明度 = max((p − 0.25) / 0.75, 0)：滑过四分之一开始变暗，滑满完全盖住。
- 往下拉过头（p < 0）不加遮罩。

钉在 `RunRecordFitnessLayoutTests.testMapVeilBlursFirstThenCoversAndClearsAtTheTop`。

## 被否

- 地图跟着内容一起滚走（第一轮做法）：负责人原话「和这个是连成一体的，但是实际上苹果的那个设计……上面一个，就是会有一个地图」。
- 对 `MAMapView` 直接 `.blur(radius:)`：离屏渲染 + 每次地图重绘都重算，耗电。
- 用 iOS 26 的系统边缘模糊：部署目标 iOS 16。

## 复核触发条件

- 部署目标升到 iOS 18（可改用 `onScrollGeometryChange`）或 iOS 26（可用系统边缘模糊）。
- 负责人装机后说模糊或变暗的节奏不对。
- 真机发现滑动掉帧或明显耗电。
- 拿到健身这一页的录屏，与上面的结构不符。
