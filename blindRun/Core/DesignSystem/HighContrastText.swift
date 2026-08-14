import SwiftUI

// MARK: - High Contrast Text

/// 高对比度文本组件，确保在深色/浅色模式下可读性。
/// 支持 Dynamic Type 自动缩放。
struct HighContrastText: View {
    /// 这个组件的名字承诺了「高对比度」，而在 2026-08-13 之前它只是选了一组固定颜色 ——
    /// 系统的「增强对比度」开关按下去，它一个像素都不变。名字挡住了这个缺口被发现。
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

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

        /// 系统「增强对比度」（设置 → 辅助功能 → 显示与文字大小 → 增强对比度）打开时的取色。
        ///
        /// 只动**次要色**这两档，理由是它们才是对比度的底：`AppColors` 现在保证的是正文阈值
        /// 4.5:1（`LowVisionChannelTests` 按固定取值断言），而 `textSecondary` 与 `primary`
        /// 正好压在那条线附近。用户显式要求增强时把它们并到 `textPrimary`，
        /// 换来的是 WCAG AAA 那一档（7:1）。
        ///
        /// `.title` / `.body` 本来就是 `textPrimary`，没有可提的空间，原样返回。
        ///
        /// 刻意**不重算一套新色板**：那要把亮/暗 × 主/次四种组合重新验一遍，
        /// 而收益只是 4.5 → 7。并到已经验过的最深色是同样效果、零新增取值。
        func color(increasedContrast: Bool) -> Color {
            guard increasedContrast else { return color }
            switch self {
            case .title, .body: return color
            case .status, .caption: return AppColors.textPrimary
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
            .foregroundColor(style.color(increasedContrast: colorSchemeContrast == .increased))
            .accessibilityLabel(text)
    }
}

// MARK: - Button Shapes

extension View {
    /// 系统「按钮形状」（设置 → 辅助功能 → 显示与文字大小 → 按钮形状）打开时给纯文字按钮描边。
    ///
    /// 只有**纯文字**按钮需要它。这个 App 绝大多数按钮是实心色块或走 `.bordered` /
    /// `.borderedProminent`（内建 style 自己响应这个开关），本来就看得出可点；
    /// 手写的「一行彩色文字 + 点击区域」才是那个开关要救的形态。
    ///
    /// 不做成全局样式：那会把已经是色块的按钮再套一层框。**逐个按需要加**，
    /// 判据就是一句话 —— 这个按钮不靠颜色还看得出是按钮吗。
    @ViewBuilder
    func buttonShapeOutlineIfNeeded(color: Color) -> some View {
        ButtonShapeOutline(color: color, content: self)
    }
}

private struct ButtonShapeOutline<Content: View>: View {
    @Environment(\.accessibilityShowButtonShapes) private var showButtonShapes

    let color: Color
    let content: Content

    var body: some View {
        if showButtonShapes {
            content.overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(color.opacity(0.6), lineWidth: 1.5)
            )
        } else {
            content
        }
    }
}

// MARK: - Step Progress Dot

/// 分步向导的进度点。走过的实心、没走过的空心（只在「不使用颜色区分」开启时）。
///
/// 抽成组件是因为它有**两个**调用点（盲人端预约向导、志愿者注册向导），
/// 而两处此前各写各的、都只靠填充色。写两遍就会漂，其中一处漏改的表现是
/// 「某些页面的进度条对色觉障碍用户还是六个一样的点」，而那种漏没人会发现。
struct StepProgressDot: View {
    let isReached: Bool
    let differentiateWithoutColor: Bool
    /// 盲人端预约向导用 12（纯圆点），志愿者注册向导用 28（圆里带序号）。
    var diameter: CGFloat = 12
    /// 圆里的序号；`nil` 表示不画。
    var stepNumber: Int?

    private var isHollow: Bool { differentiateWithoutColor && !isReached }

    var body: some View {
        ZStack {
            if isHollow {
                Circle().strokeBorder(AppColors.textSecondary, lineWidth: 2)
            } else {
                Circle().fill(isReached ? AppColors.primary : AppColors.textSecondary.opacity(0.3))
            }
            if let stepNumber {
                Text("\(stepNumber)")
                    .font(.caption.bold())
                    // 空心圈上的白字看不见。
                    .foregroundColor(isHollow ? AppColors.textSecondary : .white)
            }
        }
        .frame(width: diameter, height: diameter)
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
