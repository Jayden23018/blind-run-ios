import CoreLocation
import SwiftUI
import UIKit

// 跑步记录的两处地图（#823）：详情顶部通栏大图、列表每行 88pt 小图。共享组件的说明见 `RunRecordFitnessComponents.swift`。

// MARK: - 顶部通栏地图

/// 详情页顶部的通栏地图：真实高德、低饱和底图、配速路线，伸到导航栏下；底部至少 230pt 多段渐变融进页底，头部叠在渐变上。
/// 路线只落在「安全框」里，不压返回键、右上圆钮、头部（负责人 11-07 第 8、11 条）：
/// 上 = 安全区顶（含导航栏）+ 圆钮那一行 + 16，下 = 头部实测高度 + 16，左右各 28。
struct RunRecordMapHero<Header: View, Buttons: View>: View {
    let geometry: RunRouteGeometry
    let record: RunRecordResponse
    var highlight: VolunteerRunRecordContent.SplitRow?
    /// 页面顶的安全区（状态栏 + 导航栏）。地图伸到它下面，圆钮和取景框让开它。
    let topInset: CGFloat
    let screenHeight: CGFloat
    /// 右上有圆钮时为 true（跑者端）：取景框上沿多让一行。
    let hasTopButtons: Bool
    /// 地图整体的读屏描述。nil = 地图对读屏完全隐藏（描述在页面别处）。
    var mapAccessibilityLabel: String?
    @ViewBuilder let header: Header
    @ViewBuilder let buttons: Buttons

    @State private var headerHeight: CGFloat = 160

    static var buttonRowHeight: CGFloat { FlowMetrics.actionButtonMinHeight }
    static var gradientMinHeight: CGFloat { 230 }
    static var routeSideInset: CGFloat { 28 }
    static var routeGap: CGFloat { 16 }
    /// 取景框里至少留给路线的高度。大字号头部变高时地图跟着变高，路线不至于缩成一个点。
    static var minimumRouteHeight: CGFloat { 200 }

    var body: some View {
        let topPadding = topInset + (hasTopButtons ? Self.buttonRowHeight : 0) + Self.routeGap
        let mapHeight = max(screenHeight * 0.62, topPadding + Self.minimumRouteHeight + headerHeight + Self.routeGap)
        let gradientHeight = max(Self.gradientMinHeight, headerHeight + 70)
        ZStack(alignment: .bottomLeading) {
            RunRecordRouteMap(
                geometry: geometry,
                record: record,
                highlight: highlight,
                edgePadding: UIEdgeInsets(
                    top: topPadding,
                    left: Self.routeSideInset,
                    bottom: headerHeight + Self.routeGap,
                    right: Self.routeSideInset
                )
            )
            // 地图在滚动视图里：不接手势，上下拖都交给页面滚动。
            .allowsHitTesting(false)
            .frame(height: mapHeight)
            .overlay(alignment: .bottom) {
                RunRecordHeroGradient()
                    .frame(height: gradientHeight)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .overlay(alignment: .top) {
                if let mapAccessibilityLabel {
                    // 地图本身不进无障碍树（标记不逐个暴露），整体描述挂在头部以上这块透明区上。
                    Color.clear
                        .frame(height: max(mapHeight - headerHeight - topInset, 44)) // guard:allow small-touch-target（读屏描述区，不是按钮）
                        .padding(.top, topInset)
                        .accessibilityElement()
                        .accessibilityLabel(mapAccessibilityLabel)
                        .accessibilityIdentifier("runRecordMapDescription")
                }
            }

            header
                .padding(.horizontal, 20)
                .padding(.bottom, 4)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: RunRecordHeroHeaderHeightKey.self, value: proxy.size.height)
                    }
                )
        }
        .overlay(alignment: .topTrailing) {
            buttons
                .padding(.top, topInset)
                .padding(.trailing, 8)
        }
        .onPreferenceChange(RunRecordHeroHeaderHeightKey.self) { height in
            // 半个点以内的抖动不重新取景。
            if abs(height - headerHeight) > 0.5 { headerHeight = height }
        }
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
                    fitEdgePadding: UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12),
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
