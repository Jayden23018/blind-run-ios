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

    /// 副标题前半句：和谁一起。`name` 是上屏的掩码名。
    static func companion(name: String?) -> String {
        "和\(name?.nilIfBlank ?? "陪跑员")一起"
    }

    /// 副标题后半句：跑完后有同跑次数时才有。
    /// `togetherCount` 已含本单（`OrderDetailResponse.completedTogetherCount`），`nil` 或 0 不说次数。
    static func togetherLine(count: Int?, isFinished: Bool) -> String? {
        guard isFinished, let count, count > 0 else { return nil }
        return "你们第 \(count) 次一起跑"
    }

    /// 本月累计那一行。`summary` 取首页「本月锻炼」同一份数据。
    static func monthLine(_ summary: BlindHomeRunSummary) -> String {
        "\(summary.period) \(summary.headline)"
    }
}

enum BlindRunCardsMetrics {
    /// 里程数字 92pt（DECISION「版式」：改 v7 第 10 条的 44pt）。
    static let distanceFont: (CGFloat, Font.Weight, Font.TextStyle) = (92, .semibold, .largeTitle)
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
    var togetherCount: Int?
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
                        if !isFinished {
                            locationFreshnessRow
                        }
                        heroCard
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
        let together = BlindRunCardsCopy.togetherLine(count: togetherCount, isFinished: isFinished)
        let subtitle = ([BlindRunCardsCopy.companion(name: partnerName)] + [together].compactMap { $0 })
            .joined(separator: " · ")
        // 念法沿用 v7 那两句（「和陈一起跑步中」「跑完了，和陈一起」），不念掩码星号。
        let spokenTitle = BlindTrackingDrawerCopy.title(
            status: isFinished ? .completed : .inProgress,
            name: partnerSpokenName,
            meetSpot: nil
        ) ?? (isFinished ? BlindRunCardsCopy.finishedTitle : BlindRunCardsCopy.runningTitle)
        return VStack(alignment: .leading, spacing: 4) {
            Text(isFinished ? BlindRunCardsCopy.finishedTitle : BlindRunCardsCopy.runningTitle)
                .flowFont(FlowV2Fonts.title())
                .foregroundColor(AppColors.Flow.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .flowFont(FlowV2Fonts.callout())
                .foregroundColor(AppColors.Flow.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([spokenTitle, together].compactMap { $0 }.joined(separator: "。"))
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("blindOrderFlowStatusCard")
    }

    /// 本机定位新不新鲜：低视力用户唯一看得见 GPS 状态的地方（理由见 `BlindOrderFlowView.locationFreshnessBadge`）。
    private var locationFreshnessRow: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isLocationFresh ? AppColors.success : AppColors.warning)
                .frame(width: FlowMetrics.locationDotDiameter, height: FlowMetrics.locationDotDiameter)
                .accessibilityHidden(true)
            Text(isLocationFresh ? BlindRunCopy.locationFresh : BlindRunCopy.locationStale)
                .flowFont(FlowV2Fonts.callout())
                .foregroundColor(AppColors.Flow.secondaryText)
        }
        .padding(.top, -8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("blindOrderFlowLocationFreshness")
    }

    // MARK: - 彩色卡

    @ViewBuilder
    private var heroCard: some View {
        let card = FlowHeroCard(style: BlindHeroPalette(tone: isFinished ? .done : .running).cardStyle) {
            BlindActiveRunView(
                stats: stats,
                paceLabel: BlindRunCopy.metricPaceLabel(isFinished: isFinished),
                onHero: true,
                distanceFont: BlindRunCardsMetrics.distanceFont
            )
        }
        if isFinished {
            card.accessibilityIdentifier("blindOrderTrackingResultCard")
        } else {
            card
        }
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
