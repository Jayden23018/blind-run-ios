import SwiftUI

// 订单页 v8 卡片页（`BlindRunCardsPage`，#968）用到的两张卡：彩色卡与已完成页的陪跑员卡。

// MARK: - 彩色卡（两屏同一个位置、同一个大小）

/// 定稿图的排法：里程 92pt 左对齐、「公里」贴在数字右下；下面一行用时与每公里配速，数字在上、标签在下。
/// 颜色用现有状态色（跑步中青绿 `stateRunning`、已完成绿 `stateDone`，白字对比度逐色验过），不新增颜色。
/// 整张卡一个读屏元素，念「里程 … 用时 … 配速 …」。
struct BlindRunHeroCard: View {
    let stats: TrackStats?
    let isFinished: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(stats?.distanceKilometersText ?? "--")
                    .flowFont(BlindRunCardsMetrics.distanceFont, monospacedDigit: true)
                    .tracking(FlowMetrics.runDistanceTracking)
                    // 裁掉这个数字等于裁掉这一屏，宁可缩也不换行（同 `BlindActiveRunView`）。
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(BlindRunCardsCopy.distanceUnit)
                    .flowFont(BlindRunCardsMetrics.distanceUnitFont)
            }
            .foregroundColor(AppColors.Flow.onHeroStrong)

            // 最大字号两格并排会挤，改上下排（定稿图第二排）。不用 `ViewThatFits`，理由见 `RunExperienceRatingPicker`。
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 40))
            layout {
                metric(stats?.durationClockText, label: BlindRunCardsCopy.durationLabel)
                metric(stats?.paceClockText, label: BlindRunCardsCopy.paceLabel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BlindRunCardsMetrics.heroPadding)
        .background(
            RoundedRectangle(cornerRadius: BlindRunCardsMetrics.heroCornerRadius, style: .continuous)
                .fill(isFinished ? AppColors.Flow.stateDone : AppColors.Flow.stateRunning)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityIdentifier("blindRunCardsHero")
    }

    private func metric(_ value: String?, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value ?? "--")
                .flowFont(BlindRunCardsMetrics.metricFont, monospacedDigit: true)
                .foregroundColor(AppColors.Flow.onHeroStrong)
                .lineLimit(1)
            Text(label)
                .flowFont(BlindRunCardsMetrics.metricLabelFont)
                .foregroundColor(AppColors.Flow.onHeroBody)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 拿不到数据时说清是在获取，不念「杠杠」（同 `BlindActiveRunView.spokenLabel`）。
    private var spoken: String {
        guard let stats, let distance = stats.distanceText else { return "里程、用时和配速正在获取" }
        return ["\(BlindRunCopy.distanceSpokenLabel) \(distance)",
                stats.durationText.map { "\(BlindRunCardsCopy.durationLabel) \($0)" },
                stats.averagePaceText.map { "\(BlindRunCopy.metricPaceLabel(isFinished: isFinished)) \($0)" }]
            .compactMap { $0 }.joined(separator: "，")
    }
}

// MARK: - ⑧ 陪跑员卡

/// 定稿图：头像、名字、第二行（同跑次数，没有就写搭档状态），右边一个灰底胶囊「设为固定搭档」。
/// 点名字进这个人的页面（举报、不再匹配都在那里），动作与跑步详情那一节相同。
struct BlindRunPartnerCard: View {
    @ObservedObject var feedback: RunnerRunFeedbackViewModel
    let orderId: Int64
    var togetherLine: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let tintIndex = 2
    private var displayName: String { feedback.volunteerName ?? PartnerStreakCopy.unknownVolunteerName }
    private var spokenName: String {
        feedback.volunteerName?.unmaskedForSpeech.nilIfBlank ?? PartnerStreakCopy.unknownVolunteerName
    }
    private var secondLine: String? { togetherLine ?? feedback.partnerStatus.text }
    private var showsAddButton: Bool { feedback.partnerStatus == .notPartner && !feedback.didBlockVolunteer }

    var body: some View {
        if let row = feedback.personRow {
            RunRecordCard {
                // 最大字号下按钮排到名字下面，不并排。
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                    : AnyLayout(HStackLayout(spacing: 8))
                layout {
                    personLink(row)
                    if showsAddButton { addChip }
                }
                if let notice = feedback.favoriteNotice {
                    outcome(notice, color: AppColors.success)
                }
                if let failure = feedback.favoriteErrorMessage {
                    outcome(failure, color: AppColors.destructive)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("blindRunCardsPartner")
        }
    }

    private func personLink(_ row: PartnerRow) -> some View {
        NavigationLink {
            BlindPartnerDetailView(
                row: row,
                index: Self.tintIndex,
                setFavorite: { isFavorite in await feedback.setFavorite(isFavorite) },
                onBlocked: { await feedback.volunteerBlocked() },
                reportOrderId: orderId,
                showsFavoriteActions: feedback.partnerStatus != .unknown
            )
        } label: {
            HStack(spacing: 12) {
                if !dynamicTypeSize.isAccessibilitySize {
                    BlindPartnerAvatar(name: displayName, tint: BlindPartnerAvatar.tint(for: row, index: Self.tintIndex))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .flowFont((18, .bold, .headline))
                        .foregroundColor(AppColors.Flow.primaryText)
                    if let secondLine {
                        Text(secondLine)
                            .flowFont(FlowV2Fonts.subhead())
                            .foregroundColor(AppColors.Flow.secondaryText)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: AppTouchTarget.blindPrimary, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([spokenName, secondLine].compactMap { $0 }.joined(separator: "，"))
        .accessibilityHint("点击查看这位陪跑员，可以举报或不再匹配")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("blindRunCardsPartnerRow")
    }

    /// 灰底胶囊，看得见的部分 44pt 高，可点区撑到 64pt（撑在 label 里，外挂 frame 撑不大可点区）。
    private var addChip: some View {
        Button {
            Task { await feedback.addVolunteerToFavorites() }
        } label: {
            Text(feedback.isUpdatingFavorite ? "正在设置…" : PartnerStreakCopy.blindAddTitle)
                .flowFont((16, .semibold, .callout))
                .foregroundColor(AppColors.Flow.primaryText)
                .padding(.horizontal, 16)
                .frame(minHeight: 44) // guard:allow small-touch-target 只是看得见的胶囊，可点区是下一行的 64pt
                .background(Capsule().fill(AppColors.ButtonPalette.neutralFill))
                .frame(minHeight: AppTouchTarget.blindPrimary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(feedback.isUpdatingFavorite)
        .accessibilityLabel(PartnerStreakCopy.addFavoriteTitle(spokenName))
        // 🔴 承诺只能说到「更可能」：收藏只是派单加分。
        .accessibilityHint(PartnerStreakCopy.favoriteExplanation)
        .accessibilityIdentifier("blindRunCardsAddFavoriteButton")
    }

    private func outcome(_ text: String, color: Color) -> some View {
        Text(text)
            .font(AppFonts.body())
            .foregroundColor(color)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 8)
    }
}
