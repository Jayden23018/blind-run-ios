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

    var body: some View {
        Text(text)
            .font(style.font)
            .foregroundColor(style.color)
            .dynamicTypeSize(...DynamicTypeSize.accessibility3)
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
