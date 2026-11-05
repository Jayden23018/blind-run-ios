import SwiftUI

// 两端「我的」、账户页和陪跑员子页共用的分组卡片（陪跑员 #700 先做，盲人端 #711 复用）。
//
// 照健康 App 的分组列表：浅灰页底 `Flow.page`、白卡 `Flow.surface`、圆角 22、平的不带阴影。

enum GroupedCardMetrics {
    /// 稿子 `.group{border-radius:22px}`。
    static let cardRadius: CGFloat = 22
    /// 稿子 `.rowi{min-height:52px}`。只给陪跑员子页的只读行用；可点的行一律 64pt（`SettingsRowLabel`）。
    static let rowMinHeight: CGFloat = 52
    static let rowHorizontalPadding: CGFloat = 16
}

/// 白色圆角分组卡。里面的行自己画分隔线（`GroupedCardDivider`）。
struct GroupedCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.Flow.surface)
        .clipShape(RoundedRectangle(cornerRadius: GroupedCardMetrics.cardRadius, style: .continuous))
    }
}

/// 行与行之间的细线。有图标的行从文字起点画（左侧留空），和健康 App 一样。
struct GroupedCardDivider: View {
    var leadingInset: CGFloat = GroupedCardMetrics.rowHorizontalPadding

    var body: some View {
        Rectangle()
            .fill(AppColors.Flow.separator)
            .frame(height: 1)
            .padding(.leading, leadingInset)
            .accessibilityHidden(true)
    }
}

/// 分组卡下面的灰色说明（稿子 `.foot`）。
struct GroupedCardFootnote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundColor(AppColors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, GroupedCardMetrics.rowHorizontalPadding)
    }
}
