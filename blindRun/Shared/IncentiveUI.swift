import SwiftUI

// MARK: - 大字号下的排版

/// 大字号时把横排改成竖排。
///
/// 这不是「更好看」，是**修一类已经发生过的缺陷**：本仓库志愿者端的指标格在 AX5 下被截断成
/// 「…」（记忆 `low-vision-visual-channel-unaudited`，2026-08-22 真机跑出来的）。
/// 根因是横排 + `lineLimit(1)` + `minimumScaleFactor` —— 那套组合在字号够大时
/// **必然**丢字，而丢掉的正是低视力用户最需要放大的那个数。
///
/// 判据用 `dynamicTypeSize.isAccessibilitySize`（AX1 起为 true），不用具体档位比大小 ——
/// Apple 新增档位时那种写法会漏。
///
/// ⚠️ 本 App **不封顶** Dynamic Type（`HighContrastText` 顶部写了为什么），
/// 所以每一处横排都要么能换行、要么在这里改竖排。没有第三条路。
struct AdaptiveHStack<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var spacing: CGFloat = 12
    var alignment: HorizontalAlignment = .leading
    @ViewBuilder let content: Content

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: alignment, spacing: spacing) { content }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: spacing) { content }
        }
    }
}

// MARK: - 失败与重试

/// 加载失败时的一段文字 + 重试按钮，四个新页面共用。
struct IncentiveFailureSection: View {
    @EnvironmentObject private var speechService: SpeechService
    let message: String
    let retryTitle: String
    let identifier: String
    /// 重试了几次。同一句文案重试又失败时靠它再念一遍（#573）；`RemoteContent` 自己计数传进来。
    var attempt: Int = 0
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Button(retryTitle, action: retry)
                .buttonStyle(TextButtonStyle())
                .accessibilityIdentifier(identifier)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .announcesFailure(message, using: speechService, attempt: attempt)
    }
}
