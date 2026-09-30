# 03 · 引导绳、动画与触感

v3 规定"状态原地变化"，但没定义怎么变。本文件补上这一部分。原则：**动画只用来说明"发生了什么变化"，不做装饰**；所有动画在"减弱动态效果"开启时都有替代方案。

## 一、RopeView 几何

坐标系 342×56（按容器宽度等比缩放），头像圆心 y = 28，半径 22，姓氏字号 17 bold。

| state | 陪跑员 x | 跑者 x | 绳子 | 其他 |
|---|---|---|---|---|
| `.invited` | 24 | 318 | 从 x=50 到 292 的二次曲线，控制点 (171, 44)，**虚线** [2, 7]，线宽 2.5 | 跑者头像：空心，虚线描边 [3, 3]，字为装饰灰 |
| `.agreed` | 24 | 318 | 50 → 292 实线，控制点 (171, 46)，线宽 3 | — |
| `.departed(p)` | `24 + 244·p` | 318 | 从陪跑员右缘（x+24）到 292 的实线，下垂量 `max(2, 18·长度/242)` | x=8 处一个半径 4 的空心小圈（出发地）；陪跑员外圈半径 28 的光晕 |
| `.arrived` | 268 | 318 | 290 → 296 短直线 | 跑者外圈半径 27、线宽 2.5 的 `gold` 光环；出发地小圈 |
| `.together` | 150 | 194 | `gold` 弧线 (146,49) → (196,49)，控制点 (171,57)，线宽 3 | 用于跑步中衔接和完成页 |
| `.cancelled` | 保持上一状态的位置 | 318 | 绳子从中点断开，两段各缩短 12，变为装饰灰 | 跑者头像变灰 |

`p` 来自后端 `eta.progress`，客户端再限制在 0.1 到 0.85 之间，保证两个头像不会在出发时重叠，也不会在还没到时贴在一起。

配色：`theme = .dark`（藏青头卡、锁屏）用 `volunteerDot / runnerDot / ropeOnNavy / mutedOnNavy`；`theme = .light`（仅邀请）用 `blue / navy / blue / decorMuted`。

实现建议：一个 `Shape` 画绳子（`animatableData` 包含起点 x、终点 x、下垂量、`trim`），两个头像用 `Circle + Text` 并加 `.matchedGeometryEffect`（id 为 "volunteer"、"runner"），这样状态切换时由 SwiftUI 插值位置。

```swift
struct RopeShape: Shape {
    var startX: CGFloat
    var endX: CGFloat
    var sag: CGFloat
    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get { .init(.init(startX, endX), sag) }
        set { startX = newValue.first.first; endX = newValue.first.second; sag = newValue.second }
    }
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 342
        var p = Path()
        p.move(to: CGPoint(x: startX * s, y: 28 * s))
        p.addQuadCurve(to: CGPoint(x: endX * s, y: 28 * s),
                       control: CGPoint(x: (startX + endX) / 2 * s, y: (28 + sag) * s))
        return p
    }
}
```

读屏：整个 RopeView 是一个元素，`accessibilityLabel` 为「第 N 步，共 4 步，{状态}」，出发中再加「还有 8 分钟到」。它没有可操作项。

## 二、状态切换动画

默认曲线：`.spring(response: 0.5, dampingFraction: 0.85)`，下文简称 spring。

| 触发 | 动画 | 时长 | 触感 |
|---|---|---|---|
| 邀请 → 约好（接下成功） | ①虚线淡出，同时实线从左往右画出（`trim` 0→1，easeInOut）；②跑者头像从空心变实心（填充颜色 0.3 秒）；③头卡底色从白色过渡到藏青（0.35 秒），头卡内文字交叉淡入 | 0.6 秒 | `.success` |
| 约好（前一晚）→ 约好（出发前 30 分钟） | 白色次要按钮原地变成黄色主按钮：底色、描边、阴影同时过渡，按钮轻微缩放 0.98→1；文字从「我已经出发了」交叉淡入为「我出发了」；主角区数字从"6:35"交叉淡入为"30" | 0.35 秒 | 无（此时 App 多半不在前台） |
| 约好 → 出发（按下"我出发了"） | 陪跑员头像沿绳子滑到 p 的位置（spring），出发地小圈淡入，光晕开始呼吸；主角数字用 `numericText` 过渡 | 0.8 秒 | `.medium` 冲击 |
| 出发中 ETA 更新 | 陪跑员头像移到新位置（easeOut）；分钟数 `contentTransition(.numericText(countsDown: true))` | 0.6 秒 | 无 |
| 出发 → 快迟到 | 主角数字颜色过渡到 `gold`；提醒条从 0 高度展开 | 0.25 秒 | 无 |
| 出发 → 汇合（按下"我已到达"） | 陪跑员头像滑到 x=268（spring）；跑者外的 `gold` 光环从 0.8 倍放大到 1 倍并淡入；方位盘从 0.9 倍缩放 + 淡入 | 0.7 秒 | `.medium` 冲击 |
| 汇合 → 跑步中 | 两个头像向中间靠拢到 `.together` 的位置；绳子缩短，颜色从蓝色插值到 `gold` | 0.7 秒 | `.success` |
| 进入完成页 | ①并肩插图从 0.9 倍放大并淡入；②`gold` 绳子画出（`trim` 0→1，0.8 秒）；③留言卡上移 12pt 并淡入，延迟 0.15 秒；④时长卡同样上移淡入，再延迟 0.1 秒 | 共约 1.1 秒 | `.success`（仅一次） |
| 跑者取消 | 绳子中点断开，两段向两端各回缩 12pt；跑者头像去饱和变灰 | 0.5 秒 | 按 v3：已出发时震动 + 时间敏感推送 |

## 三、持续性动效

| 元素 | 动效 | 何时停止 |
|---|---|---|
| 出发中陪跑员光晕 | 半径 22→28 × 透明度 22%→0，2.0 秒循环，easeOut | 离开出发状态、App 进入后台、减弱动态效果 |
| `PresencePill` 圆点 | 外圈 4pt 光圈，透明度 25%↔0，1.6 秒循环 | 同上 |
| 汇合页方位扇形 | 跟随朝向旋转。先对朝向做低通滤波（α = 0.2），再用 `.interactiveSpring(response: 0.3)` 驱动；朝向变化小于 3° 不更新 | 离开汇合状态 |
| 响铃按钮 | `speaker.wave.2` 的 `symbolEffect(.variableColor.iterative)` | 到达 `ringingUntil` |
| 等待环（④b） | 每秒推进一次，不做缓动 | 结束等待或开始跑步 |

## 四、减弱动态效果（`accessibilityReduceMotion`）

- 所有位置移动、缩放、画线动画 → 0.2 秒淡入淡出，直接跳到终态
- 所有循环动效（光晕、圆点、响铃图标）→ 静态
- 方位扇形 → 仍然跟随朝向（这是信息，不是装饰），但去掉 spring，只在描述文字变化时更新

## 五、触感总表

触感跟 v3 提示级别矩阵保持一致，本表只补充本期新增的部分。

| 事件 | 触感 |
|---|---|
| 接下邀请成功 | `UINotificationFeedbackGenerator.success` |
| 按下"我出发了""我已到达集合点" | `UIImpactFeedbackGenerator(.medium)` |
| 快捷回复发送成功 | `UIImpactFeedbackGenerator(.light)` |
| 响铃请求成功 | `UIImpactFeedbackGenerator(.light)` |
| 距离首次进入 `WITHIN_10` | `UIImpactFeedbackGenerator(.light)`（v3："<10 米轻震一次"） |
| 开始跑步、进入完成页 | `.success` |
| 任何失败（网络、冲突） | `UINotificationFeedbackGenerator.error`，配合 Toast |

## 六、性能要求

- 引导绳和方位盘都用 `Shape` / `Canvas` 绘制，不要用图片序列
- 所有循环动画在视图不可见时（`onDisappear`、`scenePhase != .active`）停止
- 朝向更新频率上限 15Hz，读屏播报间隔下限 3 秒（v3）
