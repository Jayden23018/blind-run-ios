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

// MARK: - 卡片

/// 一张分节卡片：可选标题 + 内容。
///
/// 抽出来是因为积分页、固定搭档页、邀请码页三处的分节长得一样，
/// 各写各的会在圆角、内距、标题字号上慢慢漂开。
struct IncentiveCard<Content: View>: View {
    var title: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title)
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppColors.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// 页面顶部那张「一个大数字」的卡片。
///
/// 字号走 `AppFonts.largeTitle()` 而**不是** `.system(size:)` 固定磅值 ——
/// 这一页最大的那个数字恰恰是低视力用户最需要放大的东西，固定磅值不跟 Dynamic Type 走。
/// 本仓库为这条栽过一次（成就页头部原本写死 48pt，志愿者端当时一条无障碍审计都没有）。
struct IncentiveHeroCard: View {
    let value: String
    let caption: String
    /// 合成一个焦点后念出来的完整句子。分开念会让读屏用户听两遍同一个数。
    let spokenLabel: String
    var footnote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(AppFonts.largeTitle())
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(caption)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let footnote {
                Text(footnote)
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppColors.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(footnote.map { "\(spokenLabel)。\($0)" } ?? spokenLabel)
    }
}

// MARK: - 火花

/// 双人火花的一条。
///
/// 视觉上是「周数 + 进度」，抄的是 Strava 按周里程碑、Duolingo 用连续数字当进度的做法；
/// 但用的是我们真有的两个字段（`currentWeeks` / `bestWeeks`），**没有编任何客户端阈值**。
///
/// 三条无障碍处理，缺一条这块就只对看得见的人有效：
/// 1. 火焰图标是纯装饰，`accessibilityHidden(true)` —— 它没有文字承载不了的信息。
/// 2. 进度条对 VoiceOver 是空的，所以下面那行 `progressText` 不是冗余，是唯一的进度信息。
/// 3. 整块合成一个焦点，念一句完整的话。
struct StreakStrip: View {
    let partnerName: String
    let streak: PartnerStreakDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AdaptiveHStack(spacing: 8) {
                Image(systemName: "flame")
                    .font(.body.weight(.semibold))
                    .foregroundColor(AppColors.warning)
                    .accessibilityHidden(true)

                Text("连续 \(streak.currentWeeks) 周")
                    .font(AppFonts.title())
                    .foregroundColor(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if streak.isPersonalBest {
                    Text("最好成绩")
                        .font(AppFonts.caption().weight(.semibold))
                        .foregroundColor(AppColors.success)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ProgressView(value: streak.progressFraction)
                .tint(AppColors.warning)
                .accessibilityHidden(true)

            Text(streak.progressText)
                .font(AppFonts.caption())
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(streak.headline(partner: partnerName))。\(streak.progressText)。")
    }
}

// MARK: - 状态标记

/// 「对方已退出」这类状态。
///
/// 🔴 **图标 + 文字，不是灰色态。** 一个只有视觉差异的状态对读屏用户等于不存在，
/// 而这条状态的信息量很高：盲人看不到它就会以为收藏丢了、重新收藏一次，
/// 把对方刚做的退出无声撤销掉。
struct OptedOutBadge: View {
    let text: String

    var body: some View {
        AdaptiveHStack(spacing: 6) {
            Image(systemName: "person.crop.circle.badge.xmark")
                .font(.caption)
                .foregroundColor(AppColors.warning)
                .accessibilityHidden(true)
            Text(text)
                .font(AppFonts.caption().weight(.semibold))
                .foregroundColor(AppColors.warning)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - 失败与重试

/// 加载失败时的一段文字 + 重试按钮，四个新页面共用。
struct IncentiveFailureSection: View {
    let message: String
    let retryTitle: String
    let identifier: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Button(retryTitle, action: retry)
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(AppColors.primary)
                .buttonShapeOutlineIfNeeded(color: AppColors.primary)
                .accessibilityIdentifier(identifier)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
