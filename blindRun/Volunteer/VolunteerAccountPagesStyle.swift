import SwiftUI

// 陪跑员「我的」下三个子页（个人资料、我的积分、资质证书）专用的行。
// 分组卡本身（`GroupedCard`、分隔线、脚注、圆角与边距）两端共用，在 `Shared/GroupedCardStyle.swift`。
// 定稿：`docs/ui/mockups/volunteer-account-pages-20261104/`（负责人 2026-11-04 批准，#700）。
//
// 照健康 App 的分组列表：浅灰页底 `Flow.page`、白卡 `Flow.surface`、圆角 22、平的不带阴影，
// 行高不低于 52（稿子 `.rowi{min-height:52px}`）。
// ponytail: #697 合并后与 `VolunteerSecondaryCard` 合成一套，删掉重复的那份。

enum VolunteerAccountMetrics {
    /// 行首彩色方块图标的边长（稿子 `.icsq{width:34px}`）。
    static let iconSide: CGFloat = 30
    /// 方块图标右边到文字的距离；分隔线从文字起点开始画。
    static let iconSpacing: CGFloat = 12
}

/// 「字段名在左、值在右」的一行（健康详细信息的写法）。
///
/// 读屏合成一个焦点念「字段名，值」；值本身要念别的说法时（手机号只念尾号）传 `spokenValue`。
struct VolunteerAccountValueRow: View {
    let title: String
    let value: String
    var spokenValue: String?

    var body: some View {
        AdaptiveHStack(spacing: 12) {
            Text(title)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Text(value)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, GroupedCardMetrics.rowHorizontalPadding)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: GroupedCardMetrics.rowMinHeight, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)，\(spokenValue ?? value)")
    }
}

/// 行首的彩色方块图标（稿子 `.icsq`）。图标只是装饰，行文字已经说清楚，读屏不念。
struct VolunteerAccountIconSquare: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.white)
            .frame(width: VolunteerAccountMetrics.iconSide, height: VolunteerAccountMetrics.iconSide)
            .background(tint)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// 「图标 + 文字 + 箭头」的一行，给按钮和 `PhotosPicker` 当标签用。
///
/// 可点区由 `contentShape` 撑满整行：只在外面套 `frame` 撑不大可点区
/// （记忆 `button-frame-outside-label-does-not-grow-hit-area`）。
struct VolunteerAccountActionRowLabel: View {
    let title: String
    let systemImage: String
    let tint: Color
    var showsChevron = true

    var body: some View {
        HStack(spacing: VolunteerAccountMetrics.iconSpacing) {
            VolunteerAccountIconSquare(systemImage: systemImage, tint: tint)
            Text(title)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(AppColors.textSecondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, GroupedCardMetrics.rowHorizontalPadding)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: GroupedCardMetrics.rowMinHeight, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// 有图标的行之间，分隔线从文字起点开始。
    static let dividerInset = GroupedCardMetrics.rowHorizontalPadding
        + VolunteerAccountMetrics.iconSide
        + VolunteerAccountMetrics.iconSpacing
}
