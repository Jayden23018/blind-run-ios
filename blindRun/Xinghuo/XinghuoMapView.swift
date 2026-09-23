import CoreLocation
import SwiftUI

#if DEBUG
// ponytail: 一期只有演示数据，整页只在调试版编译。二期接上聚合端点后去掉这层闸，
// 并把 `snapshot` 的来源从 `XinghuoSnapshot.demo` 换成接口响应。

/// 星火页：这座城市此刻有多少人在帮忙、在跑。两端共用一个组件，差异只走密度与文案
/// （design-direction：两端不分叉组件）。长相照负责人给的 HTML 原型「星火同行 MVP」。
///
/// **这一页固定夜空，不跟随系统明暗** —— design-direction §2 记下的唯一例外
/// （项目负责人 2026-09-23）：发光的星只在深底上成立，浅色底图上它们看不见。
///
/// 读屏路径：地图、顶栏、定位按钮、图例都对读屏隐藏（信息全在摘要句里），第一个元素就是摘要句，
/// 之后依次是「听见星光」、「今日足迹」和「演示数据」角标 —— 第一次划动就听到全部数字。
struct XinghuoMapView: View {
    let role: UserRole

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var speechService: SpeechService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 页面第一次出现时的位置。星围绕它生成，地图中心也锁在它上面 ——
    /// 走动时 GPS 一更新就把地图拽回来，用户就没法拖了。
    @State private var anchor: CLLocationCoordinate2D?
    @State private var snapshot: XinghuoSnapshot?
    @State private var showsFootprints = true
    @State private var footprints: [MapPolylineItem] = []
    @State private var footprintState: FootprintState = .loading
    @State private var recenterToken = 0

    private enum FootprintState: Equatable {
        case loading
        case loaded
        case failed
    }

    private var isBlind: Bool { role == .blind }

    private var origin: CLLocationCoordinate2D {
        anchor ?? locationService.effectiveBackendLocation
    }

    var body: some View {
        ZStack {
            map
            vignette
            overlay
        }
        .environment(\.colorScheme, .dark)
        .task {
            if anchor == nil {
                anchor = locationService.effectiveBackendLocation
            }
            if snapshot == nil {
                snapshot = .demo(around: origin)
            }
            await loadFootprints()
        }
    }

    // MARK: - 地图（装饰，对读屏隐藏）

    private var map: some View {
        MapViewWrapper(
            centerCoordinate: origin,
            showsUserLocation: false,
            annotations: mapAnnotations,
            polylines: showsFootprints ? displayedFootprints : [],
            zoomLevel: 13,
            recenterToken: recenterToken,
            tracksUserLocation: false,
            animatesCenterChanges: !reduceMotion,
            isDecorative: true,
            nightSky: true,
            snapsBackToCenter: false
        )
        .ignoresSafeArea(edges: .top)
    }

    /// 每个片区画成一小簇星（`XinghuoSnapshot.sparks`，纯视觉散布），再加上「你」。
    private var mapAnnotations: [MapAnnotationItem] {
        guard let snapshot else { return [] }
        let stars = snapshot.cells(for: role).flatMap { cell in
            XinghuoSnapshot.sparks(for: cell, origin: origin).map {
                MapAnnotationItem(id: $0.id, coordinate: $0.coordinate, title: nil, subtitle: nil, kind: .xinghuoSpark($0.spark))
            }
        }
        let me = MapAnnotationItem(
            id: "xinghuo-self", coordinate: origin, title: nil, subtitle: nil, kind: .xinghuoSelf(isVolunteer: !isBlind)
        )
        return stars + [me]
    }

    /// 今天没有跑完的单时，画一条演示足迹（负责人 2026-09-23）—— 否则真机上永远看不到光带。
    /// 只在**加载成功且为空**时画：加载失败画演示线，等于把「出错了」伪装成「有数据」。
    private var displayedFootprints: [MapPolylineItem] {
        guard footprintState == .loaded, footprints.isEmpty else { return footprints }
        return [MapPolylineItem(id: "footprint-demo", coordinates: XinghuoFootprints.demoLoop(around: origin), isFootprint: true)]
    }

    /// 四周压暗（原型最后画的那层 vignette），让视线落在中间。
    private var vignette: some View {
        GeometryReader { proxy in
            RadialGradient(
                colors: [AppColors.Xinghuo.night.opacity(0), AppColors.Xinghuo.night.opacity(0.55)],
                center: UnitPoint(x: 0.5, y: 0.42),
                startRadius: min(proxy.size.width, proxy.size.height) * 0.35,
                endRadius: max(proxy.size.width, proxy.size.height) * 0.8
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - 浮层

    /// 顶栏在上、卡片贴底，**中间什么都不放** —— 那块空白不接触摸，手指落在那里拖的就是地图。
    ///
    /// 卡片始终在滚动容器里、高度贴合内容（`HugContentHeight`）：默认字号下它只有内容那么高，
    /// AX5 装不下一屏时才滚。此前整层铺满全屏的 `ScrollView` 吃掉了所有手势，地图拖不动
    /// （负责人 2026-09-23 真机反馈）。
    ///
    /// 不用 `ViewThatFits { 原样; ScrollView { 原样 } }`：那种写法在字号变化时会换一棵
    /// 视图子树，真机无障碍审计因此把这一页每个文字元素都判成「用户改不了字号」
    /// （2026-09-23，`testBlindXinghuoPageShowsSummaryAndPassesAudit`）。
    private var overlay: some View {
        VStack(spacing: 10) {
            header
            Spacer(minLength: 0)
            HStack {
                Spacer()
                recenterButton
            }
            HugContentHeight {
                ScrollView { bottomCard }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("xinghuoCardScroll")
        }
        .padding(12)
    }

    /// 字标 + 四个数。对读屏隐藏：同样的数在摘要句里念过，这里再念一遍是纯重复。
    /// 字号封顶：它只是装饰，放到 AX5 会把地图整个挤掉，而完整信息在摘要句里随字号放大。
    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("✦ 星火同行")
                .font(.system(.title3, design: .serif).weight(.medium))
                .foregroundColor(AppColors.Xinghuo.ink)
                .shadow(color: AppColors.Xinghuo.ember.opacity(0.35), radius: 9)
            if let snapshot {
                stats(snapshot)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityHidden(true)
    }

    private func stats(_ snapshot: XinghuoSnapshot) -> some View {
        HStack(spacing: 0) {
            statCell("\(snapshot.volunteersOnline)", "志愿者在线", AppColors.Xinghuo.ember)
            divider
            statCell("\(snapshot.runnersWaiting)", "视障跑者", AppColors.Xinghuo.moon)
            divider
            statCell("\(snapshot.pairsRunning)", "正在同行", AppColors.Xinghuo.ink)
            divider
            statCell(XinghuoSnapshot.kmText(snapshot.todayKm), "今日公里", AppColors.Xinghuo.ink)
        }
        .xinghuoGlass(cornerRadius: 18)
    }

    private var divider: some View {
        Rectangle()
            .fill(AppColors.Xinghuo.hairline)
            .frame(width: 1)
            .padding(.vertical, 12)
    }

    private func statCell(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(Self.numberFont(.title3))
                .foregroundColor(color)
            Text(label)
                .font(AppFonts.caption())
                .foregroundColor(AppColors.Xinghuo.muted)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
    }

    /// 数字用系统衬线（New York）：最接近原型的 Fraunces，且和 SF 一样吃 Dynamic Type。
    private static func numberFont(_ style: Font.TextStyle) -> Font {
        .system(style, design: .serif).weight(.medium).monospacedDigit()
    }

    /// 回到「你」。对读屏隐藏：地图本身对读屏隐藏，读屏用户拖不动地图，也就用不着回来。
    private var recenterButton: some View {
        Button {
            recenterToken += 1
        } label: {
            Image(systemName: "location.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(AppColors.Xinghuo.muted)
                .frame(width: 44, height: 44)
                .xinghuoGlass(cornerRadius: 14)
        }
        .accessibilityHidden(true)
    }

    private var summary: String {
        snapshot?.summaryText(for: role) ?? "正在点亮附近的星光"
    }

    private var bottomCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            headline
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(summary)
                .accessibilityIdentifier("xinghuoSummary")
                .frame(maxWidth: .infinity, alignment: .leading)

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
                        .foregroundColor(AppColors.Xinghuo.ink)
                    if let note = footprintNote {
                        Text(note)
                            .font(AppFonts.caption())
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundColor(footprintState == .failed ? AppColors.Xinghuo.ember : AppColors.Xinghuo.muted)
                    }
                }
            }
            .tint(AppColors.Xinghuo.ember)
            .frame(minHeight: isBlind ? 64 : 44)
            .accessibilityIdentifier("xinghuoFootprintToggle")

            legend

            Text("演示数据 · 仅调试版可见")
                .font(AppFonts.caption())
                .foregroundColor(AppColors.Xinghuo.muted)
        }
        .padding(16)
        .xinghuoGlass(cornerRadius: 22)
    }

    /// 卡片头：「本市 · 此刻」/ **金色大数字** + 位志愿者在线 / 一两行明细。
    ///
    /// 拼成**一个** `Text`：它就是页面第一个读屏元素，念的是完整摘要句（`accessibilityLabel`）。
    /// 拆成几个 `Text` 再合并成一个元素也能念对，但这一页的字号审计是在「一个 `Text`」
    /// 这个形状上验绿的，不换形状。
    private var headline: Text {
        var text = Text("\(snapshot?.regionName ?? "本市") · 此刻\n")
            .font(AppFonts.caption())
            .foregroundColor(AppColors.Xinghuo.muted)
        if let snapshot, snapshot.volunteersOnline > 0 {
            text = text
                + Text("\(snapshot.volunteersOnline)")
                    .font(Self.numberFont(.largeTitle))
                    .foregroundColor(AppColors.Xinghuo.ember)
                + Text(" 位志愿者在线")
                    .font(AppFonts.title())
                    .foregroundColor(AppColors.Xinghuo.ink)
        } else {
            text = text
                + Text(snapshot == nil ? "正在点亮附近的星光" : "暂时没有志愿者在线")
                    .font(AppFonts.title())
                    .foregroundColor(AppColors.Xinghuo.ink)
        }
        for line in detailLines {
            text = text + Text("\n" + line).font(AppFonts.body()).foregroundColor(AppColors.Xinghuo.muted)
        }
        return text
    }

    /// 与 `summaryText(for:)` 同口径：盲人端不提别的盲人。
    private var detailLines: [String] {
        guard let snapshot else { return [] }
        var lines: [String] = []
        if !isBlind {
            lines.append("\(snapshot.runnersWaiting) 位视障跑者在等待 · \(snapshot.pairsRunning) 对正在同行")
        }
        lines.append(
            snapshot.todayRuns > 0
                ? "今天 \(snapshot.todayRuns) 次陪跑 · 共 \(XinghuoSnapshot.kmText(snapshot.todayKm)) 公里"
                : "今天还没有完成的陪跑"
        )
        return lines
    }

    /// 图例（原型卡片最底下那一行）。对读屏隐藏：它解释的是地图，而地图本身对读屏隐藏。
    private var legend: some View {
        HStack(spacing: 14) {
            legendItem("✦", "志愿者", AppColors.Xinghuo.ember)
            if !isBlind {
                legendItem("◉", "视障跑者", AppColors.Xinghuo.moon)
            }
            legendItem("⌒", "今日足迹", AppColors.Xinghuo.ember)
        }
        .font(AppFonts.caption())
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityHidden(true)
    }

    private func legendItem(_ mark: String, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Text(mark).foregroundColor(color)
            Text(label).foregroundColor(AppColors.Xinghuo.muted)
        }
    }

    private var footprintNote: String? {
        switch footprintState {
        case .loading: return nil
        case .failed: return "足迹暂时加载不出来"
        case .loaded: return footprints.isEmpty ? "演示足迹 · 你今天还没有跑完的路线" : "你今天跑过的路线"
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

private extension View {
    /// 原型的深色玻璃：深蓝半透明 + 模糊 + 一圈极细的亮边。
    func xinghuoGlass(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background(
            shape
                .fill(AppColors.Xinghuo.glass)
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(AppColors.Xinghuo.hairline, lineWidth: 1))
        )
    }
}

/// 高度 = min(子视图的理想高度, 父视图给的高度)。用来让常驻的 `ScrollView` 按内容定高：
/// 纵向 `ScrollView` 在不限高的提议下报的是内容高度，限高时照常滚。
// ponytail: 与 PR #181 `VolunteerInviteSheet.swift` 里那份逐字相同。#181 合并后提成共用的一份。
private struct HugContentHeight: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let ideal = child.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(
            width: proposal.width ?? ideal.width,
            height: min(ideal.height, proposal.height ?? .infinity)
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}
#endif
