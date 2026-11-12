import SwiftUI

// MARK: - 订单页 v8 ⑦ 陪跑中 / ⑧ 已完成（#968）
//
// 定稿 `docs/ui/mockups/blind-run-finish-v8-20261112/`（`c-revised.png`、`DECISION.md`）。
// 开跑后不再是「地图 + 抽屉」：浅灰底，一张张卡片，两屏的彩色卡在同一个位置、同一个大小。
// 出发 / 已到达仍走 `BlindOrderTrackingView`。

extension BlindRunPhase {
    /// 这一幕走 v8 卡片页。倒计时那三秒还在地图页上（订单状态仍是「已到达」）。
    var usesRunCardsPage: Bool {
        switch self {
        case .running, .finished:
            return true
        case .beforeRun, .countdown:
            return false
        }
    }
}

enum BlindRunCardsCopy {
    static let runningTitle = "陪跑中"
    static let finishedTitle = "跑完了"
    static let distanceUnit = "公里"
    static let durationLabel = "用时"
    static let paceLabel = "每公里配速"

    /// 副标题前半句：和谁一起。`name` 是上屏的掩码名。
    static func companion(name: String?) -> String {
        "和\(name?.nilIfBlank ?? "陪跑员")一起"
    }

    /// 陪跑员卡第二行。`count` 已含本单（`OrderDetailResponse.completedTogetherCount`），`nil` 或 0 不说次数。
    static func togetherLine(count: Int?) -> String? {
        guard let count, count > 0 else { return nil }
        return "你们第 \(count) 次一起跑"
    }

    /// 本月累计那一行。`summary` 取首页「本月锻炼」同一份数据。
    static func monthLine(_ summary: BlindHomeRunSummary) -> String {
        "\(summary.period) \(summary.headline)"
    }
}

enum BlindRunCardsMetrics {
    /// 里程数字 92pt（DECISION「版式」：改 v7 第 10 条的 44pt）。
    static let distanceFont: (CGFloat, Font.Weight, Font.TextStyle) = (92, .bold, .largeTitle)
    static let distanceUnitFont: (CGFloat, Font.Weight, Font.TextStyle) = (24, .semibold, .title2)
    static let metricFont: (CGFloat, Font.Weight, Font.TextStyle) = (32, .bold, .title2)
    static let metricLabelFont: (CGFloat, Font.Weight, Font.TextStyle) = (15, .regular, .subheadline)
    static let titleFont: (CGFloat, Font.Weight, Font.TextStyle) = (30, .bold, .title)
    static let heroCornerRadius: CGFloat = 24
    static let heroPadding: CGFloat = 22
    static let cardGap: CGFloat = 14
    static let routeHeight: CGFloat = 132
    static let routeCornerRadius: CGFloat = 16
}

/// 陪跑中与已完成共用的同一个页面：顶栏 → 标题 → 彩色卡 → 调用方给的卡片 → 结果面 → 底栏。
///
/// 两屏走同一个视图分支，彩色卡的身份不变：从陪跑中到跑完，卡片原地由青绿变绿，数字不跳位置。
struct BlindRunCardsPage<TopBar: View, Cards: View, Footer: View>: View {
    let isFinished: Bool
    /// 上屏的陪跑员名（带掩码）。
    let partnerName: String?
    /// 念出来的陪跑员名（`volunteerNameForSpeech`）。
    let partnerSpokenName: String
    let stats: TrackStats?
    var isLocationFresh = true
    var isLiveSharing = false
    let topBar: TopBar
    let bottom: OrderFlowBottomActions
    /// 点卡片下面的空白 = 按一次主按钮（陪跑中「听当前状态」）。`nil` = 空白不可点。
    var onTapBlank: (() -> Void)?
    /// 彩色卡下面的卡片（已完成：路线、陪跑员、评价、本月累计）。
    @ViewBuilder let cards: () -> Cards
    /// 「刚才那一下的结果」、Mock 调试区。
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        VStack(spacing: 0) {
            topBar
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: BlindRunCardsMetrics.cardGap) {
                        header
                        BlindRunHeroCard(stats: stats, isFinished: isFinished)
                        if !isFinished {
                            shareStatusCard
                        }
                        cards()
                        footer()
                        blankArea
                    }
                    .padding(.horizontal, FlowMetrics.v2ScreenPadding)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .top)
                    .readableContentColumn()
                }
            }
            bottom
        }
        .background(AppColors.Flow.page)
    }

    // MARK: - 标题

    private var header: some View {
        // 念法沿用 v7 那两句（「和陈一起跑步中」「跑完了，和陈一起」），不念掩码星号。
        let spokenTitle = BlindTrackingDrawerCopy.title(
            status: isFinished ? .completed : .inProgress,
            name: partnerSpokenName,
            meetSpot: nil
        ) ?? (isFinished ? BlindRunCardsCopy.finishedTitle : BlindRunCardsCopy.runningTitle)
        let freshness = isLocationFresh ? BlindRunCopy.locationFresh : BlindRunCopy.locationStale
        return VStack(alignment: .leading, spacing: 2) {
            Text(isFinished ? BlindRunCardsCopy.finishedTitle : BlindRunCardsCopy.runningTitle)
                .flowFont(BlindRunCardsMetrics.titleFont)
                .foregroundColor(AppColors.Flow.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            // 定稿图：「和陈*一起 · ● 定位正常」一行。定位状态只在陪跑中有。
            HStack(spacing: 6) {
                Text(BlindRunCardsCopy.companion(name: partnerName) + (isFinished ? "" : " ·"))
                if !isFinished {
                    Circle()
                        .fill(isLocationFresh ? AppColors.success : AppColors.warning)
                        .frame(width: FlowMetrics.locationDotDiameter, height: FlowMetrics.locationDotDiameter)
                    Text(freshness)
                }
            }
            .flowFont(FlowV2Fonts.callout())
            .foregroundColor(AppColors.Flow.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isFinished ? spokenTitle : "\(spokenTitle)。\(freshness)")
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("blindOrderFlowStatusCard")
    }

    // MARK: - ⑦ 行程分享状态

    /// 只显示状态、不可点：跑步中开 / 关分享还没有拍过板（见 `blindActiveRunSafetyHubSheet` 的 `offersLiveShare`）。
    private var shareStatusCard: some View {
        RunRecordCard {
            HStack {
                Text(BlindTrackingDrawerCopy.shareRowTitle)
                    .flowFont(FlowFonts.rowValue())
                    .foregroundColor(AppColors.Flow.primaryText)
                Spacer(minLength: 8)
                Text(isLiveSharing ? BlindTrackingDrawerCopy.shareOn : BlindTrackingDrawerCopy.shareOff)
                    .flowFont(FlowFonts.rowValueEmphasized())
                    .foregroundColor(AppColors.Flow.primaryText)
            }
            .frame(minHeight: 32) // guard:allow small-touch-target 纯展示行，不可点
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("blindOrderTrackingShareStatus")
    }

    // MARK: - 底部空白

    /// 卡片与主按钮之间剩下的那一截。主按钮样子不变，可点范围扩到这里（DECISION「版式」）。
    /// 对读屏隐藏：读屏用户走主按钮本身，这里再给一个元素只是多划一下。
    @ViewBuilder
    private var blankArea: some View {
        if let onTapBlank {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture(perform: onTapBlank)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - ⑧ 已完成页彩色卡下面的几张卡

/// 路线小图 → 陪跑员与「设为固定搭档」→「这次陪跑怎么样」→ 本月累计。
///
/// 陪跑员与评价两节就是跑者跑步详情那两块（`RunnerRunRecordFeedbackSections.swift`），同一个 view model、
/// 同一套五档评价；2026-11-12 起当页放，改 11-07「评价只在跑步详情」。本月累计与首页「本月锻炼」读写同一份缓存。
/// 四块各自查各自的，失败都静默：对应那一块不出现，不挡三个数字。
struct BlindRunFinishedCards: View {
    let order: OrderDetailResponse
    let track: OrderTrackResponse?

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @StateObject private var feedback = RunnerRunFeedbackViewModel()
    @StateObject private var homeRunModel = BlindHomeIdleModel()

    var body: some View {
        VStack(alignment: .leading, spacing: BlindRunCardsMetrics.cardGap) {
            BlindRunCardsRouteMap(track: track)
            BlindRunPartnerCard(
                feedback: feedback,
                orderId: order.orderId,
                togetherLine: BlindRunCardsCopy.togetherLine(count: order.completedTogetherCount)
            )
            RunnerRunRecordReviewSection(feedback: feedback, titleInsideCard: true)
            if let summary = homeRunModel.snapshot.summary {
                Text(BlindRunCardsCopy.monthLine(summary))
                    .flowFont(FlowV2Fonts.callout())
                    .foregroundColor(AppColors.Flow.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel(summary.spokenText)
                    .accessibilityIdentifier("blindRunCardsMonthLine")
            }
        }
        // 四块一开始可能都是空的，而 `.task` 挂在空视图上不触发（记忆 `task-on-empty-view-never-fires`）。
        .frame(maxWidth: .infinity, minHeight: 1, alignment: .top) // guard:allow small-touch-target 占位，不是触达目标
        .task(id: order.orderId) {
            feedback.configure(appState: appState, speech: speechService)
            await feedback.load(order: order)
            await homeRunModel.refresh(appState: appState)
        }
    }
}

// MARK: - ⑧ 已完成页的路线小图

/// 整条路线的缩略图。装饰、不可交互：里程和用时卡片里都有文字版；要细看进跑步详情。
/// 轨迹不足两个点时不占位置。
struct BlindRunCardsRouteMap: View {
    let track: OrderTrackResponse?

    var body: some View {
        if let track, track.primaryRouteCoordinates.count >= 2 {
            TrackRouteMap(track: track)
                .frame(height: BlindRunCardsMetrics.routeHeight)
                .clipShape(RoundedRectangle(cornerRadius: BlindRunCardsMetrics.routeCornerRadius, style: .continuous))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

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
