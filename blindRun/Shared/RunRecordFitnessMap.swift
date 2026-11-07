import Combine
import CoreLocation
import SwiftUI
import UIKit

// 跑步记录的两处地图（#823）：详情顶部通栏大图、列表每行 88pt 小图。共享组件的说明见 `RunRecordFitnessComponents.swift`。

// MARK: - 顶部通栏地图

/// 详情页照健身（#823 第二轮，负责人 11-07 装机反馈第 5 条）：地图固定在页面背后，内容在它上面滚。
/// 往上滑，头部和卡片盖上来，地图逐渐模糊、变暗（`RunRecordMapVeil`）；往回滑地图慢慢显现。
/// 速度和曲线照苹果健身录屏逐帧量出来的（`RunRecordHeroLayout.veil`）：上滑 70pt 已全糊，150pt 全暗，与地图多高无关。
/// 模糊是盖在地图上的 `UIVisualEffectView`，半径随滚动连续变大（`RunRecordMapBlur`）；不对 `MAMapView` 本身做 `.blur`（每帧重绘地图太耗电）。
/// 右上圆钮固定在屏幕顶端、不跟内容滚（照健身）。
/// 路线只落在「安全框」里，不压返回键、右上圆钮、头部（负责人 11-07 第 8、11 条）：
/// 上 = 安全区顶（含导航栏）+ 圆钮那一行 + 16，下 = 头部实测高度 + 16，左右各 28。
struct RunRecordMapScrollPage<Header: View, Buttons: View, Content: View>: View {
    let geometry: RunRouteGeometry
    let record: RunRecordResponse
    var highlight: VolunteerRunRecordContent.SplitRow?
    /// 右上有圆钮时为 true（跑者端）：取景框上沿多让一行。
    let hasTopButtons: Bool
    /// 地图整体的读屏描述。nil = 地图对读屏完全隐藏（描述在页面别处）。
    var mapAccessibilityLabel: String?
    /// 地图露出来那块的 id：`ScrollViewReader.scrollTo` 滚回这里地图就完全显现（陪跑员端点单段时用）。
    var topID: String?
    @ViewBuilder let header: Header
    @ViewBuilder let buttons: Buttons
    @ViewBuilder let content: Content

    @State private var headerHeight: CGFloat = 160
    /// 放在 `@State` 而不是 `@StateObject`：整页不订阅滚动位置，每帧只有遮罩那一层重画。
    @State private var scrolled = RunRecordScrollOffset()

    private static var space: String { "runRecordMapScroll" }

    var body: some View {
        GeometryReader { proxy in
            let topInset = proxy.safeAreaInsets.top
            let edgePadding = RunRecordHeroLayout.routeInsets(topInset: topInset, hasTopButtons: hasTopButtons, headerHeight: headerHeight)
            let screenHeight = proxy.size.height + topInset + proxy.safeAreaInsets.bottom
            let mapHeight = max(screenHeight * 0.62, edgePadding.top + RunRecordHeroLayout.minimumRouteHeight + edgePadding.bottom)
            ZStack(alignment: .top) {
                RunRecordRouteMap(geometry: geometry, record: record, highlight: highlight, edgePadding: edgePadding)
                    .allowsHitTesting(false)
                    .frame(height: mapHeight)
                    .overlay { RunRecordMapVeil(scrolled: scrolled) }
                    .accessibilityHidden(true)
                ScrollView {
                    column(topInset: topInset, mapHeight: mapHeight)
                }
                .coordinateSpace(name: Self.space)
            }
            // 右上圆钮固定在屏幕顶端（照健身：往上滑它们不走）。放在滚动视图之后，叠在内容上面、先于它被读屏 / 点到。
            .overlay(alignment: .topTrailing) {
                buttons
                    .padding(.top, topInset)
                    .padding(.trailing, 8)
            }
            // 地图和内容都伸到导航栏下（照健身）；滚动后系统导航栏照常换上底色。
            .ignoresSafeArea(edges: .top)
        }
        .onPreferenceChange(RunRecordScrollOffsetKey.self) { minY in
            scrolled.value = -minY
        }
        .onPreferenceChange(RunRecordHeroHeaderHeightKey.self) { height in
            // 半个点以内的抖动不重新取景。
            if abs(height - headerHeight) > 0.5 { headerHeight = height }
        }
    }

    private func column(topInset: CGFloat, mapHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            // 地图露出来的那块：透明，滑动照常交给滚动视图。读屏描述挂在这里，跟着内容走。
            Color.clear
                .frame(height: max(mapHeight - headerHeight, topInset))
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: RunRecordScrollOffsetKey.self, value: proxy.frame(in: .named(Self.space)).minY)
                    }
                )
                .overlay(alignment: .top) { mapDescription(height: mapHeight - headerHeight - topInset, topInset: topInset) }
                .id(topID)
            header
                .padding(.horizontal, 20)
                .padding(.bottom, 4)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: RunRecordHeroHeaderHeightKey.self, value: proxy.size.height)
                    }
                )
                .readableContentColumn()
                // 渐变跟着头部走：滑动时头部下面始终垫着它，字不会直接压在地图上。
                .background(alignment: .bottom) {
                    RunRecordHeroGradient()
                        .frame(height: max(RunRecordHeroLayout.gradientMinHeight, headerHeight + 70))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            content
                .readableContentColumn()
                // 不透明的页底：卡片往上滑时把地图盖住。
                .background(AppColors.Flow.page)
        }
    }

    @ViewBuilder
    private func mapDescription(height: CGFloat, topInset: CGFloat) -> some View {
        if let mapAccessibilityLabel {
            // 地图本身不进无障碍树（标记不逐个暴露），整体描述挂在头部以上这块透明区上。
            Color.clear
                .frame(height: max(height, 44)) // guard:allow small-touch-target（读屏描述区，不是按钮）
                .padding(.top, topInset)
                .accessibilityElement()
                .accessibilityLabel(mapAccessibilityLabel)
                .accessibilityIdentifier("runRecordMapDescription")
        }
    }
}

/// 滚了多远（往上滑为正）。只给 `RunRecordMapVeil` 订阅。
@MainActor
final class RunRecordScrollOffset: ObservableObject {
    @Published var value: CGFloat = 0
}

/// 盖在固定地图上的那层：先模糊（半径连续变大），同时被页底色一点点盖住。「减少透明度」打开时不用模糊、只变暗。
private struct RunRecordMapVeil: View {
    @ObservedObject var scrolled: RunRecordScrollOffset
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let veil = RunRecordHeroLayout.veil(scrolled: scrolled.value)
        ZStack {
            // 页顶（blur 为 0）不放模糊层，免得静止看地图时系统也做模糊合成。
            if !reduceTransparency, veil.blur > 0 {
                RunRecordMapBlur(progress: veil.blur)
            }
            AppColors.Flow.page.opacity(veil.dim)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 真模糊：`UIVisualEffectView` + 暂停的 `UIViewPropertyAnimator`，`fractionComplete` 跟着滚动走，模糊半径从 0 连续变到满。
/// 不用 SwiftUI 材质的 `.opacity` 渐变：那是「清晰地图 + 半透明磨砂罩」叠着，中间帧能看见清晰的路线透出来，像鬼影；
/// 苹果健身每一帧都是一整张模糊图（2026-11-07 录屏逐帧对比）。
private struct RunRecordMapBlur: UIViewRepresentable {
    let progress: Double

    func makeUIView(context: Context) -> RunRecordBlurView { RunRecordBlurView() }

    func updateUIView(_ view: RunRecordBlurView, context: Context) {
        view.progress = CGFloat(progress)
    }
}

final class RunRecordBlurView: UIVisualEffectView {
    private var animator: UIViewPropertyAnimator?
    var progress: CGFloat = 0 {
        didSet { animator?.fractionComplete = min(max(progress, 0), 1) }
    }

    init() {
        super.init(effect: nil)
        isUserInteractionEnabled = false
        rebuildAnimator()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 暂停中的动画在 App 退到后台或视图离开窗口后会被系统结束，回到窗口时按当前进度重建。
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { rebuildAnimator() }
    }

    private func rebuildAnimator() {
        tearDownAnimator()
        effect = nil
        let animator = UIViewPropertyAnimator(duration: 1, curve: .linear) { [weak self] in
            self?.effect = UIBlurEffect(style: .systemThinMaterial)
        }
        animator.pausesOnCompletion = true
        animator.fractionComplete = min(max(progress, 0), 1)
        self.animator = animator
    }

    private func tearDownAnimator() {
        guard let animator else { return }
        animator.stopAnimation(true)
        self.animator = nil
    }

    deinit {
        animator?.stopAnimation(true)
    }
}

private struct RunRecordScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// 通栏地图的尺寸常量与路线取景框（负责人 11-07 第 11 条），抽成纯函数好让用例钉住四边。
enum RunRecordHeroLayout {
    static let buttonRowHeight: CGFloat = FlowMetrics.actionButtonMinHeight
    static let gradientMinHeight: CGFloat = 230
    static let routeSideInset: CGFloat = 28
    static let routeGap: CGFloat = 16
    /// 标注图片以坐标为中心画（公里圆 20pt、休息 / 高亮胶囊约 22pt 高），取景只按折线外框算，四边再让出半个标注。
    static let annotationMargin: CGFloat = 12
    /// 取景框里至少留给路线的高度。大字号头部变高时地图跟着变高，路线不至于缩成一个点。
    static let minimumRouteHeight: CGFloat = 200

    /// 苹果健身录屏逐帧量出来的曲线（2026-11-07，健身记录.mov，1px = 1pt，量地图区域亮度与清晰度）：
    /// 上滑 70pt 已全糊（26pt 明显、40pt 重度），150pt 前后全暗；与地图高度无关。
    /// 往下拉过头（`scrolled` 为负）不加遮罩。页底色在下面的卡片盖上来时接手，所以变暗滑满即 1。
    static let blurDistance: CGFloat = 70
    static let dimDistance: CGFloat = 150

    static func veil(scrolled: CGFloat) -> (blur: Double, dim: Double) {
        let positive = max(scrolled, 0)
        return (blur: Double(min(positive / blurDistance, 1)), dim: Double(min(positive / dimDistance, 1)))
    }

    /// 上 = 安全区顶（含导航栏）+ 圆钮那一行（有圆钮时）+ 16；下 = 头部实测高度 + 16；左右 28；四边再加半个标注。
    static func routeInsets(topInset: CGFloat, hasTopButtons: Bool, headerHeight: CGFloat) -> UIEdgeInsets {
        UIEdgeInsets(
            top: topInset + (hasTopButtons ? buttonRowHeight : 0) + routeGap + annotationMargin,
            left: routeSideInset + annotationMargin,
            bottom: headerHeight + routeGap + annotationMargin,
            right: routeSideInset + annotationMargin
        )
    }
}

private struct RunRecordHeroHeaderHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// 透明 → 35% → 75% → 95% → 页底，缓动分布（负责人 11-07 第 9 条：「苹果会有一个比较好的渐变」）。
/// `Flow.page` 亮暗各一值，所以深浅两套是同一份写法。
struct RunRecordHeroGradient: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: AppColors.Flow.page.opacity(0), location: 0),
                .init(color: AppColors.Flow.page.opacity(0.35), location: 0.22),
                .init(color: AppColors.Flow.page.opacity(0.75), location: 0.48),
                .init(color: AppColors.Flow.page.opacity(0.95), location: 0.72),
                .init(color: AppColors.Flow.page, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// 地图右上的圆钮：44pt 可见、64pt 可点，读屏有名字（负责人 11-07 第 3 条）。
/// 可点区挂在 label 里（记忆 button-frame-outside-label-does-not-grow-hit-area）。
struct RunRecordMapCircleButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let accessibilityHint: String
    let identifier: String
    var isActive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundColor(isActive ? AppColors.background : AppColors.primary)
                .frame(width: 44, height: 44) // guard:allow small-touch-target（看得见的圆，可点区是下面的 64pt）
                .background(
                    Circle()
                        .fill(isActive ? AppColors.primary : AppColors.Flow.surface)
                        .shadow(color: .black.opacity(0.18), radius: 4, y: 1)
                )
                .frame(width: FlowMetrics.actionButtonMinHeight, height: FlowMetrics.actionButtonMinHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - 列表小地图

/// 列表每行右侧 88pt 圆角小地图（负责人 11-07 第 1 条，方案 A）：真实高德、低饱和底图、不可交互、读屏隐藏。
/// 路线单色 `paceFast` + 近黑描边，起点绿点终点红点。画不出路线（没有点：超过 90 天留存期 / 后端没补算；
/// 或所有点重合：只跑了几秒）时显示浅灰底 + 跑步图标 —— 只画底块像图片加载失败（2026-10-03 试用反馈）。
struct RunRecordListMap: View {
    let points: [RunLatLng]?
    static let side: CGFloat = 88
    /// 起终点圆点以坐标为中心画，四边让出整个圆点再留几点空，整条路线都在 88pt 里（负责人 11-07 第二轮第 4 条）。
    static let routeInsets = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

    var body: some View {
        Group {
            if let points, RunRouteShape.hasExtent(points) {
                let coordinates = points.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
                MapViewWrapper(
                    centerCoordinate: Self.center(of: coordinates),
                    showsUserLocation: false,
                    annotations: Self.endpoints(coordinates),
                    polylines: [
                        MapPolylineItem(id: "list-outline", coordinates: coordinates, isPrimary: true, routeStyle: .outline),
                        // 单色「快」那一档：`fractions` 只有一个 0（同详情页没有配速采样时）。
                        MapPolylineItem(id: "list-route", coordinates: coordinates, routeStyle: .pace(indexes: [], fractions: [0]))
                    ],
                    tracksUserLocation: false,
                    animatesCenterChanges: false,
                    fitEdgePadding: Self.routeInsets,
                    isDecorative: true,
                    mutedBasemap: true
                )
                .allowsHitTesting(false)
            } else {
                ZStack {
                    AppColors.secondaryBackground
                    Image(systemName: "figure.run")
                        .font(.title2)
                        .foregroundColor(AppColors.textSecondary)
                }
            }
        }
        .frame(width: Self.side, height: Self.side)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityHidden(true)
    }

    static func center(of coordinates: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D {
        let lats = coordinates.map(\.latitude)
        let lngs = coordinates.map(\.longitude)
        return CLLocationCoordinate2D(
            latitude: ((lats.min() ?? 0) + (lats.max() ?? 0)) / 2,
            longitude: ((lngs.min() ?? 0) + (lngs.max() ?? 0)) / 2
        )
    }

    private static func endpoints(_ coordinates: [CLLocationCoordinate2D]) -> [MapAnnotationItem] {
        guard let first = coordinates.first, let last = coordinates.last else { return [] }
        return [
            MapAnnotationItem(id: "list-start", coordinate: first, title: nil, subtitle: nil, kind: .runEndpoint(isStart: true, compact: true)),
            MapAnnotationItem(id: "list-end", coordinate: last, title: nil, subtitle: nil, kind: .runEndpoint(isStart: false, compact: true))
        ]
    }
}
