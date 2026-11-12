import SwiftUI

// 订单页 v8 卡片页（`BlindRunCardsPage`，#968）用到的卡：彩色卡、计划进度卡、已完成页的陪跑员卡。
// 尺寸与颜色照 `docs/ui/mockups/blind-run-finish-v8-20261112/c-revised.html` 的数值。

// MARK: - 颜色与卡片底

/// 彩色卡的渐变（DECISION 第 5 条，负责人 2026-11-12 装机后选定稿图这一组，不用纯色状态色）。
/// 亮暗同值，理由同 `AppColors.Flow` 的头卡状态色。白字压最浅一端：青绿 6.74、绿 6.27。
/// 放在文件内而不是 `FlowPalette.swift`：那个文件已到单文件行数上限。
enum BlindRunCardsPalette {
    static let runningTop = Color(uiColor: UIColor(rgb: 0x0B4A53))
    static let runningBottom = Color(uiColor: UIColor(rgb: 0x0F6570))
    static let doneTop = Color(uiColor: UIColor(rgb: 0x124F2B))
    static let doneBottom = Color(uiColor: UIColor(rgb: 0x1B6E3F))

    /// CSS `linear-gradient(160deg, …)` 换成单位坐标：方向朝下偏右 20°，起止点按 370×208 的卡算。
    static func hero(isFinished: Bool) -> LinearGradient {
        LinearGradient(
            colors: isFinished ? [doneTop, doneBottom] : [runningTop, runningBottom],
            startPoint: UnitPoint(x: 0.35, y: -0.23),
            endPoint: UnitPoint(x: 0.65, y: 1.23)
        )
    }
}

/// 这一页的白卡：圆角 20，内边距由调用方按定稿图给。
struct BlindRunCardSurface<Content: View>: View {
    var insets = EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18)
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(insets)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.Flow.surface)
        .clipShape(RoundedRectangle(cornerRadius: BlindRunCardsMetrics.cardCornerRadius, style: .continuous))
    }
}

// MARK: - 彩色卡（两屏同一个位置、同一个大小）

/// 定稿图的排法：里程 92pt 左对齐、「公里」贴在数字右下；下面一行用时与每公里配速，数字在上、标签在下。
/// 还没有里程时不摆三个「--」：数字那一层照样占位（卡片大小不变），上面盖两行字说明这一刻。
/// 整张卡一个读屏元素，念「里程 … 用时 … 配速 …」。
struct BlindRunHeroCard: View {
    let stats: TrackStats?
    let isFinished: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var hasDistance: Bool { stats?.distanceKilometersText != nil }

    var body: some View {
        ZStack(alignment: .topLeading) {
            numbers
                .opacity(hasDistance ? 1 : 0)
            if !hasDistance {
                waiting
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BlindRunCardsMetrics.heroInsets)
        .background(
            RoundedRectangle(cornerRadius: BlindRunCardsMetrics.cardCornerRadius, style: .continuous)
                .fill(BlindRunCardsPalette.hero(isFinished: isFinished))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityIdentifier("blindRunCardsHero")
    }

    private var numbers: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(stats?.distanceKilometersText ?? "0.00")
                    .flowFont(BlindRunCardsMetrics.distanceFont, monospacedDigit: true)
                    .tracking(FlowMetrics.runDistanceTracking)
                    // 裁掉这个数字等于裁掉这一屏，宁可缩也不换行（同 `BlindActiveRunView`）。
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(BlindRunCardsCopy.distanceUnit)
                    .flowFont(BlindRunCardsMetrics.distanceUnitFont)
            }
            .foregroundColor(AppColors.Flow.onHeroStrong)
            // 定稿图这一行行高等于字号（92）；系统字体自带的上下留白约多 18pt，标准字号档收回来。
            .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 0 : -BlindRunCardsMetrics.distanceLineTrim)

            // 最大字号两格并排会挤，改上下排（定稿图第二排）。不用 `ViewThatFits`，理由见 `RunExperienceRatingPicker`。
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 40))
            layout {
                metric(stats?.durationClockText, label: BlindRunCardsCopy.durationLabel)
                metric(stats?.paceClockText, label: BlindRunCardsCopy.paceLabel)
            }
        }
    }

    /// 还没有里程的那一刻。不写数字（没有就是没有），不写「刚开跑」（中途重进这一页时也会走到这里）。
    private var waiting: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(BlindRunCardsCopy.waitingTitle(isFinished: isFinished))
                .flowFont(BlindRunCardsMetrics.waitingTitleFont)
                .foregroundColor(AppColors.Flow.onHeroStrong)
            Text(BlindRunCardsCopy.waitingBody(isFinished: isFinished))
                .flowFont(BlindRunCardsMetrics.waitingBodyFont)
                .foregroundColor(AppColors.Flow.onHeroBody)
        }
        .fixedSize(horizontal: false, vertical: true)
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

// MARK: - ⑦ 计划进度卡

/// 「计划跑 5 公里」+ 一条进度横条（样子照定稿图「每公里」卡的横条；每公里分段没有数据，那张卡不做）。
/// 只用订单上的计划里程和已记录的里程，两个都是真数：没填计划里程整张卡不出现；还没有里程时横条是空的。
struct BlindRunPlanCard: View {
    let plannedMeters: Int?
    let stats: TrackStats?

    var body: some View {
        if let plannedMeters, plannedMeters > 0, let plan = RunPlanFormat.plannedDistance(meters: plannedMeters) {
            let ratio = (stats?.distanceMeters).map { max($0, 0) / Double(plannedMeters) }
            let progress = ratio.map { $0 >= 1 ? BlindRunCardsCopy.planReached : "\(Int(($0 * 100).rounded(.down)))%" }
            BlindRunCardSurface(insets: EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18)) {
                HStack {
                    Text(BlindRunCardsCopy.planTitle(plan))
                        .flowFont(FlowFonts.rowValue())
                    Spacer(minLength: 8)
                    if let progress {
                        Text(progress)
                            .flowFont(FlowFonts.rowValueEmphasized(), monospacedDigit: true)
                    }
                }
                .foregroundColor(AppColors.Flow.primaryText)
                Capsule()
                    .fill(AppColors.ButtonPalette.neutralFill)
                    .frame(height: BlindRunCardsMetrics.planBarHeight)
                    .overlay(alignment: .leading) {
                        GeometryReader { geometry in
                            Capsule()
                                .fill(BlindRunCardsPalette.runningBottom)
                                .frame(width: geometry.size.width * min(ratio ?? 0, 1))
                        }
                    }
                    .padding(.top, 12)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(BlindRunCardsCopy.planSpoken(plan: plan, progress: progress))
            .accessibilityIdentifier("blindRunCardsPlan")
        }
    }
}

// MARK: - ⑧ 陪跑员卡

/// 定稿图：头像、名字、第二行（同跑次数，没有就写搭档状态），右边一个灰底胶囊「设为固定搭档」。
/// 一行，卡高 72：上下内边距只留 4，名字那一行和胶囊各自的可点区 64 正好填满卡片，左右相邻不重叠。
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
            BlindRunCardSurface(insets: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
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
                .lineLimit(1)
                .fixedSize()
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
            .padding(.bottom, 8)
    }
}
