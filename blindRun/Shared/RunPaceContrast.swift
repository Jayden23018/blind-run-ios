import SwiftUI
import UIKit

/// 「增强对比度」下配速颜色的形状冗余（#579）。
///
/// 负责人 2026-10-28 选方案 A：**不换** DECISIONS D8 的配速三色，开关打开时给路线加宽描边、
/// 给图例色条与分段条加边框 —— 改动面最小，形状冗余对色弱用户同样有用。
/// 一个值同时管地图（高德渲染器，UIKit）与 SwiftUI 色条，四种组合由 `RunPaceContrastTests` 钉住。
struct RunPaceContrast: Equatable {
    var isIncreased = false
    var isDark = false

    init(isIncreased: Bool = false, isDark: Bool = false) {
        self.isIncreased = isIncreased
        self.isDark = isDark
    }

    init(environment: EnvironmentValues) {
        self.init(isIncreased: environment.colorSchemeContrast == .increased, isDark: environment.colorScheme == .dark)
    }

    /// 路线垫底的近黑描边：平时 11pt（配速线 6.5pt，两侧各露约 2.3pt）；增强时 16pt，两侧各露约 4.8pt，比平时翻一倍。
    var routeOutlineWidth: CGFloat { isIncreased ? Self.increasedRouteOutlineWidth : RunRouteGlyph.outlineWidth }
    /// 色条边框：平时没有；增强时 1.5pt。
    var barBorderWidth: CGFloat { isIncreased ? 1.5 : 0 }
    /// 亮色近黑、暗色纯白：压各自的页面底色都远过 3:1（WCAG 1.4.11）。
    var barBorderRGB: UInt32 { isDark ? 0xFFFFFF : 0x1C1C1E }

    static let increasedRouteOutlineWidth: CGFloat = 16
}

/// 色条（图例、分段条）在增强对比度下的边框。自己读环境，调用点只加一行。
struct RunPaceBarBorder<S: InsettableShape>: ViewModifier {
    let shape: S
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let contrast = RunPaceContrast(isIncreased: colorSchemeContrast == .increased, isDark: colorScheme == .dark)
        content.overlay {
            if contrast.barBorderWidth > 0 {
                shape.strokeBorder(Color(uiColor: UIColor(rgb: contrast.barBorderRGB)), lineWidth: contrast.barBorderWidth)
            }
        }
    }
}
