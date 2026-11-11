import CoreLocation
import SwiftUI

// MARK: - 订单页 v7 外壳：上半屏地图 + 下半屏抽屉（#918）

/// 地图要画的原始数据。坐标一律 GCJ-02（订单起点、陪跑员位置后端就是 GCJ-02；
/// 「我」由调用方取 `LocationService.effectiveBackendLocation`，那里做过唯一一次转换）。
struct BlindTrackingMapInput {
    var meetPoint: CLLocationCoordinate2D?
    var volunteer: CLLocationCoordinate2D?
    var me: CLLocationCoordinate2D?
    var route: [CLLocationCoordinate2D] = []
    /// 对方那颗图钉的名字。盲人端看到的是陪跑员；陪跑员订单页（#945）传「跑者」。
    var peerTitle = "陪跑员"
}

/// 出发 / 已到达 / 陪跑中 / 已完成四态共用的**同一个**页面（稿 ⑤–⑧ 与 A/B/C 三帧）。
///
/// - 地图在上，状态切换只换抽屉内容；地图视图的身份在四态间不变，不重建。
/// - 抽屉两档：收起（默认，看不到竖线）/ 拉到顶（竖线完整）；中间跟手，竖线透明度随进度渐变。
/// - 读屏打开：竖线恒显示，排在抽屉内容最后；拖动条给「展开 / 收起」两个读屏动作。
/// - 最大字号或横屏：不画地图，抽屉占满整屏可滚动。
///
/// 竖线（`BlindOrderTimelineView`）与顶栏（`BlindOrderTopBar`，`.onMap`）都是 #917 的组件，由调用方传进来。
struct BlindOrderTrackingView<TopBar: View, Drawer: View, Timeline: View, Footer: View>: View {
    let status: RunOrderStatus
    let mapInput: BlindTrackingMapInput
    /// 返回 / 重复当前状态 / 右上角求助。压在地图上；最大字号下排在抽屉上面。
    let topBar: TopBar
    let bottom: OrderFlowBottomActions
    @ViewBuilder let drawer: () -> Drawer
    @ViewBuilder let timeline: () -> Timeline
    /// 「刚才那一下的结果」（含「不再匹配」的结果一行）、Mock 调试区。排在竖线**之前**：它们是这一刻的事，竖线是回顾。
    @ViewBuilder let footer: () -> Footer

    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @State private var isExpanded = false
    @State private var dragTranslation: CGFloat = 0
    /// 上一次拖动松手的时刻。拖完松手时按钮的点按也可能触发，不挡掉会把刚拖到的那一档又切回去。
    @State private var lastDragEndedAt: Date?

    private var showsMap: Bool {
        BlindOrderTrackingLayout.showsMap(
            isAccessibilitySize: dynamicTypeSize.isAccessibilitySize,
            isCompactHeight: verticalSizeClass == .compact
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                if showsMap {
                    mapLayout(size: geometry.size)
                } else {
                    fullDrawer
                }
            }
            bottom
        }
        .background(AppColors.Flow.page)
    }

    // MARK: - 地图 + 抽屉

    private func mapLayout(size: CGSize) -> some View {
        let mapHeight = (size.height * BlindOrderTrackingLayout.mapHeightFraction).rounded()
        // 抽屉圆角压进地图一点，看起来是从地图下面拉出来的。
        let collapsedTop = max(BlindOrderTrackingLayout.expandedMapStrip, mapHeight - 20)
        let expandedTop = min(collapsedTop, BlindOrderTrackingLayout.expandedMapStrip)
        let baseTop = isExpanded ? expandedTop : collapsedTop
        let top = min(collapsedTop, max(expandedTop, baseTop + dragTranslation))
        let progress = BlindOrderTrackingLayout.drawerProgress(top: top, collapsedTop: collapsedTop, expandedTop: expandedTop)

        return ZStack(alignment: .top) {
            BlindTrackingMap(status: status, input: mapInput, size: CGSize(width: size.width, height: mapHeight))
                .frame(height: mapHeight)
            // 读屏顺序：顶栏在前（返回、喇叭、求助），然后才是抽屉。
            topBar
                .accessibilitySortPriority(1)
            drawerPanel(progress: progress, collapsedTop: collapsedTop, expandedTop: expandedTop)
                .frame(height: max(0, size.height - top))
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }

    private func drawerPanel(progress: CGFloat, collapsedTop: CGFloat, expandedTop: CGFloat) -> some View {
        let opacity = BlindOrderTrackingLayout.timelineOpacity(progress: progress, voiceOverRunning: voiceOverEnabled)
        return VStack(spacing: 0) {
            // 给拖动条的那一截。拖动条本身画在 overlay 里，命中区 64pt 盖住内容顶部一截。
            Color.clear.frame(height: BlindTrackingDrawerMetrics.handleReservedHeight)
            ScrollView {
                drawerColumn(timelineOpacity: opacity)
            }
        }
        .background(
            AppColors.Flow.surface
                .clipShape(RoundedRectangle(cornerRadius: BlindTrackingDrawerMetrics.cornerRadius, style: .continuous))
                .flowCardShadow()
                .ignoresSafeArea(edges: .bottom)
        )
        .overlay(alignment: .top) {
            drawerHandle(collapsedTop: collapsedTop, expandedTop: expandedTop)
        }
    }

    // MARK: - 最大字号 / 横屏：抽屉占满

    private var fullDrawer: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                drawerColumn(timelineOpacity: 1)
                    .padding(.top, 8)
            }
        }
        .background(AppColors.Flow.surface)
    }

    private func drawerColumn(timelineOpacity: Double) -> some View {
        VStack(alignment: .leading, spacing: FlowMetrics.v2SectionGap) {
            drawer()
            footer()
            timeline()
                .opacity(timelineOpacity)
                // 看不见的竖线不该被读屏念到；读屏打开时透明度恒为 1，所以这条只对不开读屏的人生效。
                .accessibilityHidden(timelineOpacity == 0)
                .allowsHitTesting(timelineOpacity > 0.5)
        }
        .padding(.horizontal, FlowMetrics.v2ScreenPadding)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .readableContentColumn()
    }

    // MARK: - 拖动条

    /// 点一下切换两档（XCUITest 的 `tap()` 够得着，读屏动作够不着 —— 记忆
    /// `xcuitest-cannot-invoke-accessibility-actions`），拖动跟手，读屏给「展开 / 收起」两个动作。
    private func drawerHandle(collapsedTop: CGFloat, expandedTop: CGFloat) -> some View {
        Button {
            if let lastDragEndedAt, Date().timeIntervalSince(lastDragEndedAt) < BlindTrackingDrawerMetrics.tapAfterDragWindow { return }
            setExpanded(!isExpanded)
        } label: {
            Capsule()
                .fill(AppColors.Flow.secondaryText.opacity(0.45))
                .frame(width: 40, height: 5) // guard:allow small-touch-target 只是看得见的那一小条，命中区是下面 64pt 的整行
                .padding(.top, 10)
                .frame(maxWidth: .infinity, minHeight: BlindTrackingDrawerMetrics.handleHitHeight, alignment: .top)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 6)
                .onChanged { dragTranslation = $0.translation.height }
                .onEnded { value in
                    let base = isExpanded ? expandedTop : collapsedTop
                    let predicted = base + value.predictedEndTranslation.height
                    lastDragEndedAt = Date()
                    setExpanded(predicted < (collapsedTop + expandedTop) / 2)
                }
        )
        .accessibilityLabel(BlindTrackingDrawerCopy.handleLabel)
        .accessibilityValue(isExpanded ? BlindTrackingDrawerCopy.handleExpanded : BlindTrackingDrawerCopy.handleCollapsed)
        .accessibilityHint(BlindTrackingDrawerCopy.handleHint)
        .accessibilityAction(named: Text(BlindTrackingDrawerCopy.expandAction)) { setExpanded(true) }
        .accessibilityAction(named: Text(BlindTrackingDrawerCopy.collapseAction)) { setExpanded(false) }
        .accessibilityIdentifier("blindOrderTrackingDrawerHandle")
    }

    /// 「减弱动态效果」打开时瞬时切换，不做位移插值（理由同 `BlindOrderFlowView.transitionAnimation`）。
    private func setExpanded(_ expanded: Bool) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.86)) {
            isExpanded = expanded
            dragTranslation = 0
        }
    }
}

enum BlindTrackingDrawerMetrics {
    static let cornerRadius: CGFloat = 24
    /// 拖动条的命中区高度（盲人端可点区下限 64pt）。
    static let handleHitHeight: CGFloat = 64
    /// 内容区顶部为拖动条让出的高度。比命中区小：命中区的下半截盖在标题上，标题本身不可点。
    static let handleReservedHeight: CGFloat = 28
    /// 拖动松手后这段时间内的点按算作同一次手势，不再切换。
    static let tapAfterDragWindow: TimeInterval = 0.4
}

// MARK: - 地图

/// 地图是装饰（`isDecorative`）、不可交互：同样的信息（陪跑员多远、在哪集合）抽屉里都有文字版，
/// 与订单页原先那张地图（`peerMapSection`）同一条规则。
private struct BlindTrackingMap: View {
    let status: RunOrderStatus
    let input: BlindTrackingMapInput
    let size: CGSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let content = BlindOrderTrackingLayout.mapContent(
            status: status,
            meetPoint: input.meetPoint,
            volunteer: input.volunteer,
            me: input.me,
            route: input.route,
            size: size,
            peerTitle: input.peerTitle
        ) {
            MapViewWrapper(
                centerCoordinate: content.center,
                showsUserLocation: content.showsUserLocation,
                annotations: content.annotations,
                polylines: content.polylines,
                zoomLevel: content.zoomLevel,
                tracksUserLocation: false,
                animatesCenterChanges: !reduceMotion,
                isDecorative: true
            )
            .allowsHitTesting(false)
            .accessibilityIdentifier("blindOrderTrackingMap")
        } else {
            // 一个点都拿不到（没有集合点坐标、没有陪跑员位置、本机没定位）：纯色底，不编位置。
            AppColors.Flow.surfaceSubtle
                .accessibilityHidden(true)
        }
    }
}
