import SwiftUI

#if DEBUG
// ponytail: 一期只有演示数据，整页只在调试版编译。二期接上聚合端点后去掉这层闸，
// 并把 `snapshot` 的来源从 `XinghuoSnapshot.demo` 换成接口响应。

/// 星火页：这座城市此刻有多少人在帮忙、在跑。两端共用一个组件，差异只走密度与文案
/// （design-direction：两端不分叉组件）。
///
/// 读屏路径：地图与顶部统计都对读屏隐藏（信息全在摘要句里），第一个元素就是摘要句，
/// 之后依次是「听见星光」、「今日足迹」和「演示数据」角标 —— 第一次划动就听到全部数字。
struct XinghuoMapView: View {
    let role: UserRole

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var speechService: SpeechService
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var snapshot: XinghuoSnapshot?
    @State private var showsFootprints = true
    @State private var footprints: [MapPolylineItem] = []
    @State private var footprintState: FootprintState = .loading

    private enum FootprintState: Equatable {
        case loading
        case loaded
        case failed
    }

    private var isBlind: Bool { role == .blind }

    var body: some View {
        ZStack {
            map
            overlay
        }
        .task {
            if snapshot == nil {
                snapshot = .demo(around: locationService.effectiveBackendLocation)
            }
            await loadFootprints()
        }
    }

    // MARK: - 地图（装饰，对读屏隐藏）

    private var map: some View {
        let cells = snapshot?.cells(for: role) ?? []
        return MapViewWrapper(
            centerCoordinate: locationService.effectiveBackendLocation,
            showsUserLocation: locationService.isAuthorized,
            annotations: cells.map { cell in
                let tier = XinghuoSnapshot.tier(forCount: cell.count)
                return MapAnnotationItem(
                    id: cell.id,
                    coordinate: cell.center,
                    title: nil,
                    subtitle: nil,
                    kind: cell.kind == .volunteer ? .volunteerStar(tier: tier) : .runnerCluster(tier: tier)
                )
            },
            polylines: showsFootprints ? footprints : [],
            zoomLevel: 13,
            tracksUserLocation: false,
            animatesCenterChanges: false,
            isDecorative: true
        )
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - 浮层

    /// 放大字号时卡片可能比屏幕高，所以整层始终放在滚动容器里；`minHeight` 撑满一屏，
    /// 装得下时卡片照样贴底。
    ///
    /// 不用 `ViewThatFits { 原样; ScrollView { 原样 } }`：那种写法在字号变化时会换一棵
    /// 视图子树，真机无障碍审计因此把这一页每个文字元素都判成「用户改不了字号」
    /// （2026-09-23，`testBlindXinghuoPageShowsSummaryAndPassesAudit`）。
    private var overlay: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 12) {
                    if let snapshot {
                        stats(snapshot)
                    }
                    Spacer(minLength: 0)
                    bottomCard
                }
                .padding(.horizontal, FlowMetrics.pageHorizontalPadding)
                .padding(.vertical, 12)
                .frame(minHeight: proxy.size.height)
            }
        }
    }

    /// 顶部四个数。对读屏隐藏：同样的数在摘要句里念过，这里再念一遍是纯重复。
    private func stats(_ snapshot: XinghuoSnapshot) -> some View {
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: 8),
            count: dynamicTypeSize.isAccessibilitySize ? 2 : 4
        )
        return LazyVGrid(columns: columns, spacing: 8) {
            statCell("\(snapshot.volunteersOnline)", "志愿者在线", AppColors.warning)
            statCell("\(snapshot.runnersWaiting)", "视障跑者", AppColors.primary)
            statCell("\(snapshot.pairsRunning)", "正在同行", AppColors.Flow.primaryText)
            statCell(XinghuoSnapshot.kmText(snapshot.todayKm), "今日公里", AppColors.Flow.primaryText)
        }
        .padding(12)
        .background(AppColors.Flow.surface.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: FlowMetrics.buttonRadius, style: .continuous))
        .accessibilityHidden(true)
    }

    private func statCell(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(AppFonts.title())
                .foregroundColor(color)
            Text(label)
                .font(AppFonts.caption())
                .foregroundColor(AppColors.Flow.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }

    private var summary: String {
        snapshot?.summaryText(for: role) ?? "正在点亮附近的星光"
    }

    private var bottomCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(summary)
                .font(AppFonts.title())
                .foregroundColor(AppColors.Flow.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("xinghuoSummary")

            FlowActionButton(
                "听见星光",
                systemImage: "waveform",
                accessibilityHint: "朗读身边有多少人在线"
            ) {
                speechService.speak(summary, priority: .onDemand)
            }

            Toggle(isOn: $showsFootprints) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("今日足迹")
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.Flow.primaryText)
                    if let note = footprintNote {
                        Text(note)
                            .font(AppFonts.caption())
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundColor(footprintState == .failed ? AppColors.warning : AppColors.Flow.secondaryText)
                    }
                }
            }
            .frame(minHeight: isBlind ? 64 : 44)
            .accessibilityIdentifier("xinghuoFootprintToggle")

            Text("演示数据 · 仅调试版可见")
                .font(AppFonts.caption())
                .foregroundColor(AppColors.Flow.secondaryText)
        }
        .padding(16)
        .background(AppColors.Flow.surface)
        .clipShape(RoundedRectangle(cornerRadius: FlowMetrics.orderCardRadius, style: .continuous))
    }

    private var footprintNote: String? {
        switch footprintState {
        case .loading: return nil
        case .failed: return "足迹暂时加载不出来"
        case .loaded: return footprints.isEmpty ? "今天还没有你跑过的路线" : "你今天跑过的路线"
        }
    }

    // MARK: - 我的足迹（真实数据）

    private func loadFootprints() async {
        do {
            let orders = try await appState.orders.myOrders().content
            var items: [MapPolylineItem] = []
            for orderID in XinghuoFootprints.todaysCompletedOrderIDs(in: orders) {
                let coordinates = try await appState.safety.orderTrack(orderId: orderID).primaryRouteCoordinates
                guard coordinates.count >= 2 else { continue }
                items.append(MapPolylineItem(id: "footprint-\(orderID)", coordinates: coordinates, isFootprint: true))
            }
            footprints = items
            footprintState = .loaded
        } catch {
            // 切走 tab 时 `.task` 被取消 —— 那不是加载失败，别把「加载不出来」留在屏幕上。
            guard !Task.isCancelled else { return }
            footprintState = .failed
        }
    }
}
#endif
