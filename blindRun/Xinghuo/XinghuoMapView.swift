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
/// 摘要句的 hint 念「演示数据」；之后是「听见星光」（足迹加载失败时还有一句提示），最后是卡片把手
/// （展开 / 收起）—— 第一次划动就听到全部数字。
struct XinghuoMapView: View {
    let role: UserRole

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var speechService: SpeechService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// 页面第一次出现时的位置。星围绕它生成，地图中心也锁在它上面 ——
    /// 走动时 GPS 一更新就把地图拽回来，用户就没法拖了。
    @State private var anchor: CLLocationCoordinate2D?
    @State private var snapshot: XinghuoSnapshot?
    @State private var footprints: [MapPolylineItem] = []
    @State private var footprintState: FootprintState = .loading
    @State private var recenterToken = 0
    /// 卡片收起 / 展开。想多看地图的人把它划下去（负责人 2026-09-23）；跨启动记住，默认展开。
    @AppStorage("xinghuo.cardCollapsed") private var isCardCollapsed = false
    /// 把手拖动中的竖向位移。松手归零时按弹簧回位（减弱动态效果时 `handleOffset` 恒为 0，不跟手也就无所谓回位）。
    @GestureState(resetTransaction: Transaction(animation: XinghuoMapView.cardSnapAnimation))
    private var handleDrag: CGFloat = 0

    private static let cardSnapAnimation = Animation.spring(response: 0.35, dampingFraction: 0.85)
    /// 松手时（按惯性预测的）位移超过它就换档，否则回弹。
    private static let cardSnapDistance: CGFloat = 60
    /// 展开态往下拖时跟手的上限。再往下就压到标签栏上了。
    private static let cardMaxPull: CGFloat = 120
    /// 收起态往上拖只给一点橡皮筋反馈：面板贴底，往上平移会在下面露出一道缝。
    private static let cardRubberBand: CGFloat = 40

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
            // 足迹一律显示，没有开关（负责人 2026-09-24）。
            polylines: displayedFootprints,
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
            cardPanel
        }
        .padding(12)
        // 往下拖卡片时别让它画到标签栏上。
        .clipped()
    }

    /// 把手 + 卡片，共用一块玻璃。标识符沿用 `xinghuoCardScroll`：审计用例靠它量面板的上沿。
    ///
    /// 把手在 `ZStack` 里**后画**、内容顶部让出同样高度，而不是放进 `VStack` 第一个：
    /// 读屏遍历顺序跟**绘制顺序**走，`accessibilitySortPriority` 在这里真机实测排不动
    /// （2026-09-23，把手照样排在摘要句前面；记忆 `swiftui-traversal-order-follows-paint-order`）。
    private var cardPanel: some View {
        ZStack(alignment: .top) {
            HugContentHeight {
                ScrollView {
                    bottomCard.padding(.top, handleHeight)
                }
            }
            cardHandle
        }
        .xinghuoGlass(cornerRadius: 22)
        .offset(y: handleOffset)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("xinghuoCardScroll")
    }

    /// 拖动**只挂在把手上**：挂在整张卡上会和卡片里的 `ScrollView`（AX5 时要滚）抢手势。
    /// 轻点也能换档 —— 拖不动的人（手抖、单手牵绳）照样用得上。
    ///
    /// 读屏：一个按钮，value 念当前档位，双击换档、上下轻扫也能换档（可调节）；
    /// 排在卡片内容**之后**（见 `cardPanel`），第一个读屏元素仍是摘要句。
    private var cardHandle: some View {
        Capsule()
            .fill(AppColors.Xinghuo.muted)
            .frame(width: 36, height: 5)
            .frame(maxWidth: .infinity)
            .frame(height: handleHeight)
            .contentShape(Rectangle())
            .onTapGesture { setCardCollapsed(!isCardCollapsed) }
            .gesture(
                DragGesture(minimumDistance: 10)
                    .updating($handleDrag) { value, state, _ in state = value.translation.height }
                    .onEnded { value in
                        let travel = value.predictedEndTranslation.height
                        if !isCardCollapsed, travel > Self.cardSnapDistance {
                            setCardCollapsed(true)
                        } else if isCardCollapsed, travel < -Self.cardSnapDistance {
                            setCardCollapsed(false)
                        }
                    }
            )
            .accessibilityElement()
            .accessibilityLabel("星火卡片")
            .accessibilityValue(isCardCollapsed ? "已收起" : "已展开")
            .accessibilityHint(isCardCollapsed ? "轻点两下展开，看图例" : "轻点两下收起，多看地图")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { setCardCollapsed(!isCardCollapsed) }
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: setCardCollapsed(false)
                case .decrement: setCardCollapsed(true)
                @unknown default: break
                }
            }
            .accessibilityIdentifier("xinghuoCardHandle")
    }

    /// 把手的命中区高度：盲人端 64pt，志愿者端 44pt。
    private var handleHeight: CGFloat { isBlind ? 64 : 44 }

    /// 展开态只许往下拖（跟手），收起态只许往上拖（橡皮筋）。减弱动态效果时不跟手。
    private var handleOffset: CGFloat {
        guard !reduceMotion else { return 0 }
        return isCardCollapsed
            ? max(min(handleDrag, 0) / 3, -Self.cardRubberBand)
            : min(max(handleDrag, 0), Self.cardMaxPull)
    }

    private func setCardCollapsed(_ collapsed: Bool) {
        guard collapsed != isCardCollapsed else { return }
        withAnimation(reduceMotion ? nil : Self.cardSnapAnimation) {
            isCardCollapsed = collapsed
        }
    }

    /// 字标 + 四个数。对读屏隐藏：同样的数在摘要句里念过，这里再念一遍是纯重复。
    ///
    /// ⚠️ **不要给它封字号**（`.dynamicTypeSize(...)`）。对读屏隐藏的元素照样会被真机审计检查，
    /// 2026-09-23 加了封顶之后，这一排九个文字全部被判成「用户改不了字号」。
    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 演示标记挂在顶栏（spec：一期必须看得见「演示数据」），不占卡片的高度。
            // 读屏那一侧由摘要句的 hint 念。
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("✦ 星火同行")
                    .font(.system(.title3, design: .serif).weight(.medium))
                    .foregroundColor(AppColors.Xinghuo.ink)
                    .shadow(color: AppColors.Xinghuo.ember.opacity(0.35), radius: 9)
                Text("演示数据")
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.Xinghuo.muted)
            }
            if let snapshot {
                stats(snapshot)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
    }

    /// 大字号时四列改两列：四列平分宽度，「86.5」这种不能折行的数字会被截断
    /// （2026-09-23 真机审计 `Text clipped`）。改版前的写法就是这样，审计验绿过。
    private func stats(_ snapshot: XinghuoSnapshot) -> some View {
        let columns = dynamicTypeSize.isAccessibilitySize ? 2 : 4
        let cells: [(String, String, Color)] = [
            ("\(snapshot.volunteersOnline)", "志愿者在线", AppColors.Xinghuo.ember),
            ("\(snapshot.runnersWaiting)", "视障跑者", AppColors.Xinghuo.moon),
            ("\(snapshot.pairsRunning)", "正在同行", AppColors.Xinghuo.ink),
            (XinghuoSnapshot.kmText(snapshot.todayKm), "今日公里", AppColors.Xinghuo.ink),
        ]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: columns), spacing: 0) {
            ForEach(cells.indices, id: \.self) { index in
                statCell(cells[index].0, cells[index].1, cells[index].2, divided: index % columns != 0)
            }
        }
        .xinghuoGlass(cornerRadius: 18)
    }

    /// 分隔线挂在格子左边的 overlay 上，高度跟格子走。单独放一个 `Rectangle` 进 `HStack`
    /// 会在竖直方向无限伸展，把整排统计撑满剩余的屏幕（2026-09-23 真机截图实见）。
    private func statCell(_ value: String, _ label: String, _ color: Color, divided: Bool) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(Self.numberFont(.title3))
                .foregroundColor(color)
            Text(label)
                .font(AppFonts.caption())
                .foregroundColor(AppColors.Xinghuo.muted)
        }
        .multilineTextAlignment(.center)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .leading) {
            if divided {
                Rectangle()
                    .fill(AppColors.Xinghuo.hairline)
                    .frame(width: 1)
                    .padding(.vertical, 12)
            }
        }
    }

    /// 数字用系统衬线（New York）：最接近原型的 Fraunces，且和 SF 一样吃 Dynamic Type。
    private static func numberFont(_ style: Font.TextStyle) -> Font {
        .system(style, design: .serif).weight(.medium).monospacedDigit()
    }

    /// 回到「你」。对读屏隐藏：地图本身对读屏隐藏，读屏用户拖不动地图，也就用不着回来。
    ///
    /// 看得见的只有 36pt 的一小块半透明底（负责人 2026-09-24：「更小、更透明」），
    /// 能点的范围仍是盲人端 64 / 志愿者端 44：看得见但点不准的低视力用户是用手指点它的。
    private var recenterButton: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return Button {
            recenterToken += 1
        } label: {
            Image(systemName: "location.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(AppColors.Xinghuo.muted)
                .frame(width: 36, height: 36)
                .background(shape.fill(AppColors.Xinghuo.night.opacity(0.45)))
                .overlay(shape.stroke(AppColors.Xinghuo.hairline, lineWidth: 1))
                .frame(width: isBlind ? 64 : 44, height: isBlind ? 64 : 44, alignment: .bottomTrailing)
                .contentShape(Rectangle())
        }
        .accessibilityHidden(true)
    }

    private var summary: String {
        snapshot?.summaryText(for: role) ?? "正在点亮附近的星光"
    }

    /// 两档共用一棵视图：收起时摘要缩成一行、「听见星光」缩成行尾的图标按钮，图例藏起来。
    /// 两档里读屏元素一个不少 —— 摘要句（hint 念「演示数据」）、「听见星光」，足迹加载失败时还有那句提示。
    private var bottomCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isCardCollapsed {
                // 一段文字 + 一个按钮，不是两个次级操作并排（design-direction §4 管的是后者）。
                HStack(alignment: .center, spacing: 12) {
                    summaryText
                    listenIconButton
                }
            } else {
                summaryText
                FlowActionButton(
                    "听见星光",
                    systemImage: "waveform",
                    accessibilityHint: "朗读身边有多少人在线"
                ) {
                    speakSummary()
                }
            }

            // 足迹一律显示，开关去掉了（负责人 2026-09-24）；加载失败仍必须看得见（spec）。
            if footprintState == .failed {
                Text("足迹暂时加载不出来")
                    .font(AppFonts.caption())
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundColor(AppColors.Xinghuo.ember)
            }

            if !isCardCollapsed {
                legend
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    private var summaryText: some View {
        (isCardCollapsed ? compactHeadline : headline)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(summary)
            .accessibilityHint("演示数据，仅调试版可见")
            .accessibilityIdentifier("xinghuoSummary")
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 收起态行尾的「听见星光」。金底 + 深色图标，与展开态那枚金色主按钮同一种颜色语义。
    private var listenIconButton: some View {
        let side: CGFloat = isBlind ? 64 : 44
        return Button(action: speakSummary) {
            Image(systemName: "waveform")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(AppColors.Xinghuo.night)
                .frame(width: side, height: side)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppColors.Xinghuo.ember)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("听见星光")
        .accessibilityHint("朗读身边有多少人在线")
    }

    private func speakSummary() {
        speechService.speak(summary, priority: .onDemand)
    }

    /// 收起态的摘要：一行「N 位志愿者在线」。读屏念的仍是完整摘要句（`accessibilityLabel(summary)`）。
    private var compactHeadline: Text {
        guard let snapshot, snapshot.volunteersOnline > 0 else {
            return Text(snapshot == nil ? "正在点亮附近的星光" : "暂时没有志愿者在线")
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(AppColors.Xinghuo.ink)
        }
        return Text("\(snapshot.volunteersOnline)")
            .font(Self.numberFont(.title2))
            .foregroundColor(AppColors.Xinghuo.ember)
            + Text(" 位志愿者在线")
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(AppColors.Xinghuo.ink)
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
                    .font(Self.numberFont(.title))
                    .foregroundColor(AppColors.Xinghuo.ember)
                + Text(" 位志愿者在线")
                    .font(AppFonts.body().weight(.semibold))
                    .foregroundColor(AppColors.Xinghuo.ink)
        } else {
            text = text
                + Text(snapshot == nil ? "正在点亮附近的星光" : "暂时没有志愿者在线")
                    .font(AppFonts.body().weight(.semibold))
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
        .accessibilityHidden(true)
    }

    private func legendItem(_ mark: String, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Text(mark).foregroundColor(color)
            Text(label).foregroundColor(AppColors.Xinghuo.muted)
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
