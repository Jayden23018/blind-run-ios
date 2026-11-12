import CoreLocation
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

    /// 彩色卡还没有里程时盖在上面的两行字。陪跑中不说「刚开跑」：中途重进这一页、第一次数据还没回来时也是这两行。
    static func waitingTitle(isFinished: Bool) -> String {
        isFinished ? "稍等一下" : "已开跑"
    }

    static func waitingBody(isFinished: Bool) -> String {
        isFinished ? "这次的里程、用时和配速正在获取。" : "跑出一段路后，这里显示里程、用时和配速。"
    }

    /// 计划进度卡。`plan` 是「5 公里」「800 米」。
    static func planTitle(_ plan: String) -> String { "计划跑 \(plan)" }
    static let planReached = "已跑到"

    static func planSpoken(plan: String, progress: String?) -> String {
        guard let progress else { return planTitle(plan) }
        return progress == planReached ? "\(planTitle(plan))，已经跑到" : "\(planTitle(plan))，已跑 \(progress)"
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
    /// 系统字体 92pt 一行比字号高出的上下留白，各收回这么多（定稿图行高 = 字号）。
    static let distanceLineTrim: CGFloat = 8
    static let metricFont: (CGFloat, Font.Weight, Font.TextStyle) = (28, .bold, .title2)
    static let metricLabelFont: (CGFloat, Font.Weight, Font.TextStyle) = (15, .regular, .subheadline)
    static let titleFont: (CGFloat, Font.Weight, Font.TextStyle) = (30, .bold, .title)
    static let waitingTitleFont: (CGFloat, Font.Weight, Font.TextStyle) = (44, .bold, .largeTitle)
    static let waitingBodyFont: (CGFloat, Font.Weight, Font.TextStyle) = (17, .regular, .body)
    /// 以下照 `c-revised.html`：`.cpage` 左右 16、`.ccard` 圆角 20、彩色卡内边距 22 / 22 / 20、
    /// 陪跑中卡间距 14、已完成卡间距 10、路线小图高 84。
    static let pagePadding: CGFloat = 16
    static let cardCornerRadius: CGFloat = 20
    static let heroInsets = EdgeInsets(top: 22, leading: 22, bottom: 20, trailing: 22)
    static let runningGap: CGFloat = 14
    static let finishedGap: CGFloat = 10
    static let routeHeight: CGFloat = 84
    static let routeCornerRadius: CGFloat = 16
    static let planBarHeight: CGFloat = 12
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
    /// 订单上的计划里程（米）。`nil` = 没填，计划进度卡不出现。
    var plannedDistanceMeters: Int?
    let topBar: TopBar
    let bottom: OrderFlowBottomActions
    /// 点卡片下面的空白 = 按一次主按钮（陪跑中「听当前状态」）。`nil` = 空白不可点。
    var onTapBlank: (() -> Void)?
    /// 彩色卡下面的卡片（已完成：路线、陪跑员、评价、本月累计）。
    @ViewBuilder let cards: () -> Cards
    /// 「刚才那一下的结果」、Mock 调试区。
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        // 骨架与陪跑员端跑步中 / 跑完了共用（`RunCardsScaffold`，#972）。
        RunCardsScaffold(gap: gap, topBar: topBar, bottom: bottom, onTapBlank: onTapBlank, header: header) {
            BlindRunHeroCard(stats: stats, isFinished: isFinished)
                .accessibilityIdentifier("blindRunCardsHero")
            if !isFinished {
                BlindRunPlanCard(plannedMeters: plannedDistanceMeters, stats: stats)
                    .accessibilityIdentifier("blindRunCardsPlan")
                shareStatusCard
            }
            cards()
            footer()
        }
    }

    /// 卡与卡的间距：陪跑中 14，已完成 10（标题到彩色卡两屏都是 14，彩色卡因此在同一个位置）。
    private var gap: CGFloat {
        isFinished ? BlindRunCardsMetrics.finishedGap : BlindRunCardsMetrics.runningGap
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
        // 定稿图：「和陈*一起 · ● 定位正常」一行。定位状态只在陪跑中有。
        return RunCardsHeader(
            title: isFinished ? BlindRunCardsCopy.finishedTitle : BlindRunCardsCopy.runningTitle,
            companion: BlindRunCardsCopy.companion(name: partnerName),
            isLocationFresh: isFinished ? nil : isLocationFresh
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isFinished ? spokenTitle : "\(spokenTitle)。\(freshness)")
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("blindOrderFlowStatusCard")
    }

    // MARK: - ⑦ 行程分享状态

    /// 只显示状态、不可点：跑步中开 / 关分享还没有拍过板（见 `blindActiveRunSafetyHubSheet` 的 `offersLiveShare`）。
    private var shareStatusCard: some View {
        BlindRunCardSurface(insets: EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18)) {
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
        VStack(alignment: .leading, spacing: BlindRunCardsMetrics.finishedGap) {
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
                    // 定稿图：这一行离评价卡 8，比卡间距少 2。
                    .padding(.top, 8 - BlindRunCardsMetrics.finishedGap)
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
/// 轨迹不足两个点、或所有点重合时不占位置。
///
/// 🔴 配置照跑步记录列表小图（`RunRecordListMap`），不用 `TrackRouteMap`：`mutedBasemap` 那条路径会在地图
/// 摆到真实尺寸后重新取景（`AMapContainer.configureRunRecordMap`）。不开的话第一次取景按 0×0 算，
/// 84pt 高的扁图上只看得到一段路线（负责人 2026-11-12 装机第三轮）。
struct BlindRunCardsRouteMap: View {
    let track: OrderTrackResponse?

    /// 起终点圆点以坐标为中心画，四边让出整个圆点再留几点空（同 `RunRecordListMap.routeInsets`）。
    static let routeInsets = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

    var body: some View {
        if let coordinates = track?.primaryRouteCoordinates, coordinates.count >= 2,
           let first = coordinates.first, let last = coordinates.last,
           RunRouteShape.hasExtent(coordinates.map { RunLatLng(lat: $0.latitude, lng: $0.longitude) }) {
            MapViewWrapper(
                centerCoordinate: RunRecordListMap.center(of: coordinates),
                showsUserLocation: false,
                annotations: [
                    MapAnnotationItem(
                        id: "cards-route-start", coordinate: first, title: nil, subtitle: nil,
                        kind: .runEndpoint(isStart: true, compact: true)
                    ),
                    MapAnnotationItem(
                        id: "cards-route-end", coordinate: last, title: nil, subtitle: nil,
                        kind: .runEndpoint(isStart: false, compact: true)
                    )
                ],
                polylines: [
                    MapPolylineItem(id: "cards-route-outline", coordinates: coordinates, isPrimary: true, routeStyle: .outline),
                    MapPolylineItem(id: "cards-route", coordinates: coordinates, routeStyle: .pace(indexes: [], fractions: [0]))
                ],
                tracksUserLocation: false,
                animatesCenterChanges: false,
                fitEdgePadding: Self.routeInsets,
                isDecorative: true,
                mutedBasemap: true
            )
            .frame(height: BlindRunCardsMetrics.routeHeight)
            .clipShape(RoundedRectangle(cornerRadius: BlindRunCardsMetrics.routeCornerRadius, style: .continuous))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
