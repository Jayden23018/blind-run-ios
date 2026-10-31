import SwiftUI

/// 语音下单读回轮整单里的一行：「出发 / 结束 / 时间 / 时长」+ 值。
///
/// 值**允许换行**（#527）：出发、结束地址常常一行放不下，原来是单行 + 缩到 60%，
/// 而用户（低视力用户与陪同的明眼人）正是靠这一屏核对要不要下单 —— 缩到看不清就等于没给他核对。
///
/// - 横排时不用 `Spacer`：它和能折行的值是两个弹性视图，会对半分宽度，长地址只用得上半行
///   （记忆 `flexible-spacer-steals-half-the-row`）。名字 `fixedSize`，值占满剩下的宽度、右对齐。
/// - 无障碍字号下名字和值上下排，免得值被挤成一窄列。
/// - 上屏的值以全角「）」结尾时补一个窄空格：真机审计会把顶着框右边的「）」判成 `Text clipped`
///   （记忆 `text-clipped-audit-trailing-fullwidth-paren`）。读屏标签用原串。
struct BookingRecapRow: View {
    let name: String
    let value: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        layout {
            Text(name)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
                .fixedSize()
            Text(Self.displayValue(value))
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(AppColors.textPrimary)
                .multilineTextAlignment(stacked ? .leading : .trailing)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: stacked ? .leading : .trailing)
                .accessibilityLabel(value)
        }
    }

    static func displayValue(_ value: String) -> String {
        value.hasSuffix("）") ? value + "\u{202F}" : value
    }
}
