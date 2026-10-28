import SwiftUI

/// 按下缩放。`scale == 1` 时与 `.plain` 等价 —— 盲人端三种样式走这条路径，外观不变。
///
/// 「减弱动态效果」打开时不缩放：缩放是位移类动效，03 §四要求降级。
struct FlowPressScaleStyle: ButtonStyle {
    let scale: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
