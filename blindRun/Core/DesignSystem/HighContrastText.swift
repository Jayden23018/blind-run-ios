import SwiftUI

// MARK: - High Contrast Text

/// 高对比度文本组件，确保在深色/浅色模式下可读性。
/// 支持 Dynamic Type 自动缩放。
struct HighContrastText: View {
    let text: String
    let style: TextStyle

    enum TextStyle {
        case title
        case body
        case status
        case caption

        var font: Font {
            switch self {
            case .title: return AppFonts.title()
            case .body: return AppFonts.body()
            case .status: return .title3.bold()
            case .caption: return AppFonts.caption()
            }
        }

        var color: Color {
            switch self {
            case .title: return AppColors.textPrimary
            case .body: return AppColors.textPrimary
            case .status: return AppColors.primary
            case .caption: return AppColors.textSecondary
            }
        }
    }

    init(_ text: String, style: TextStyle = .body) {
        self.text = text
        self.style = style
    }

    /// 刻意**不封顶** Dynamic Type。
    ///
    /// 这里此前是 `.dynamicTypeSize(...DynamicTypeSize.accessibility3)`。封顶本身是个合法技巧，
    /// 但用在这个 App 上是反的：AX4 / AX5 正是**低视力用户实际会设的档位**
    /// （body 在 AX3 是 40pt、AX5 是 53pt，约为默认 17pt 的 235% 与 310%），
    /// 封在 AX3 等于把最后两级从目标用户手里拿走。
    ///
    /// 而且全仓只有这一个组件封顶，其余文本都不封 —— 于是同一屏里一部分字会长、一部分不会，
    /// 得到的是**不一致的缩放**，比两个极端都差。
    ///
    /// 保留封顶能防裁切，所以这个改动把风险转移到了布局上：
    /// `blindRunUITests/AccessibilityAuditTests` 的 `.dynamicType` 审计是它的守门人，**必须真机跑过**。
    /// 本组件承载的都是短标题（「实名认证」「助盲跑」「创建预约」），裁切风险低，但低不等于零。
    var body: some View {
        Text(text)
            .font(style.font)
            .foregroundColor(style.color)
            .accessibilityLabel(text)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        HighContrastText("标题文字", style: .title)
        HighContrastText("正文内容", style: .body)
        HighContrastText("匹配中", style: .status)
        HighContrastText("辅助说明", style: .caption)
    }
    .padding()
}
