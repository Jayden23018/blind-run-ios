import CoreLocation
import SwiftUI

// 志愿者首页的最近陪跑卡。主体与排序在 `VolunteerProfileFirstScreenView.swift`，取值在 `VolunteerHomeSummaryCards.swift`。

extension VolunteerProfileFirstScreen {
    // MARK: - 最近陪跑

    /// 一张卡：公里数 + 「和王* · 地点」+ 下面一整条高德地图上的路线（#694 v3）。
    ///
    /// 数据走 `GET /api/orders/mine/run-records`（「记录」标签页同一个接口），
    /// 不再用 `dispatchSummary.recentOrders`：那份没有公里数和路线。
    @ViewBuilder
    var recentSection: some View {
        sectionHeader(VolunteerProfileCopy.recentSectionTitle) {
            NavigationLink {
                RunRecordHistoryView(role: .volunteer)
            } label: {
                linkLabel(VolunteerProfileCopy.recentLinkTitle)
            }
            .accessibilityLabel("我的陪跑记录")
            .accessibilityHint(VolunteerProfileCopy.recentLinkHint)
            .accessibilityIdentifier("volunteerProfileRecentAllLink")
        }

        // 加载中 / 失败（会念）/ 内容走 `RemoteContent`（#865）；失败原来只上屏不念。
        RemoteContent(
            recentRun.state,
            // 带上分区名：首页几块同时在加载时，读屏要分得清是哪一块。
            loadingLabel: "\(VolunteerProfileCopy.recentSectionTitle)。\(VolunteerHomeIncentiveCopy.loading)",
            failureIdentifier: "volunteerProfileRecentRetryButton",
            retryTitle: VolunteerProfileCopy.recentRetry,
            retry: { Task { await recentRun.load(appState: appState) } }
        ) { content in
            if let content {
                NavigationLink {
                    VolunteerRunRecordView(orderId: content.orderId)
                } label: {
                    recentCard(content)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(content.spoken)
                .accessibilityHint(VolunteerProfileCopy.recentCardHint)
                .accessibilityIdentifier("volunteerProfileRecentRunCard")
            } else {
                recentMessage(
                    // 跑过的人两个月没跑：不说「完成陪跑后会显示在这里」，那句是对新人说的。
                    hasCompletedRuns ? VolunteerProfileCopy.recentNoneLately : VolunteerProfileCopy.recentEmpty,
                    identifier: "volunteerProfileRecentEmpty"
                )
            }
        }
    }

    /// 成就数据说跑过至少一次。拿不到成就数据时按「没跑过」处理 —— 那只影响空态的措辞，两句都是真话。
    private var hasCompletedRuns: Bool {
        (incentive.summary?.achievements?.totalCompleted ?? 0) > 0
    }

    private func recentCard(_ content: VolunteerHomeRecentRunContent) -> some View {
        VolunteerSecondaryCard {
            VStack(alignment: .leading, spacing: 12) {
                VolunteerSecondaryCardHeader(
                    title: VolunteerProfileCopy.recentCardTitle,
                    symbol: .system("figure.run"),
                    tint: AppColors.primary,
                    meta: content.dateText,
                    showsChevron: true
                )
                recentTexts(content)
                recentRoute(content.route)
            }
        }
    }

    private func recentTexts(_ content: VolunteerHomeRecentRunContent) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let distance = content.distanceText {
                (Text(distance).font(AppFonts.largeTitle())
                    + Text(" 公里").font(AppFonts.body().weight(.semibold))
                        .foregroundColor(AppColors.textSecondary))
                    .foregroundColor(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let detail = content.detailText {
                Text(detail)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 这一次的路线画在**真实的高德地图上**：看得出在哪条路、哪个公园跑的
    /// （负责人 2026-11-04 看截图后要求；此前右侧只是一条折线草图）。
    ///
    /// 整条宽图放在公里数下面，不再是右侧小方块 —— 小方块里看不清街道和地名。
    /// 地图是装饰：不可拖动（点卡片照常进跑后详情）、对读屏隐藏（同样的信息在卡片的读屏标签里）。
    /// 写法同 `CompletedTrackSummaryView`：主路线 + 起点 / 终点标注。
    ///
    /// 🔴 **缩放级别在这里按路线范围与地图实际宽高算好再传进去**，不靠 `AMapContainer` 的主路线取景：
    /// 2026-11-04 真机，这张 140pt 高的扁图上取景没有生效，停在默认 15 级，一圈 1 公里的路线下半截出框。
    /// 地图宽度要等排版才知道，所以包一层 `GeometryReader`，拿到宽度再建地图。
    ///
    /// 🔴 **画不出路线就什么都不画**（#694）：`route` 为 nil 的判据在
    /// `VolunteerHomeRecentRunContent`（空、null、点全部重合）。不画空地图，也不画占位图标。
    ///
    /// UI 测试构建没有高德 key 时 `MapViewWrapper` 退成占位图，那**不是生产形态**。
    @ViewBuilder
    private func recentRoute(_ route: [RunLatLng]?) -> some View {
        if let route, !route.isEmpty {
            let coordinates = route.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
            GeometryReader { proxy in
                if proxy.size.width > 0 {
                    Self.recentRouteMap(coordinates, size: proxy.size)
                }
            }
            .frame(height: Self.routeMapHeight)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// 地图本身。抽成静态函数是为了单测能直接读这些参数（装饰、不跟随定位、主路线、起终点）——
    /// UI 测试构建默认关地图，截图用例又不断言，参数被改了不会有别的信号。
    static func recentRouteMap(_ coordinates: [CLLocationCoordinate2D], size: CGSize) -> MapViewWrapper {
        let mapCenter = center(of: coordinates)
        let first = coordinates.first ?? mapCenter
        let last = coordinates.last ?? mapCenter
        return MapViewWrapper(
            centerCoordinate: mapCenter,
            showsUserLocation: false,
            annotations: [
                MapAnnotationItem(
                    id: "recent-route-start",
                    coordinate: first,
                    title: "起点", subtitle: nil, kind: .routeStart
                ),
                MapAnnotationItem(
                    id: "recent-route-end",
                    coordinate: last,
                    title: "终点", subtitle: nil, kind: .routeEnd
                )
            ],
            polylines: [MapPolylineItem(id: "recent-route", coordinates: coordinates, isPrimary: true)],
            zoomLevel: fittingZoomLevel(coordinates, in: size, padding: routeMapPadding),
            tracksUserLocation: false,
            animatesCenterChanges: false,
            fitEdgePadding: UIEdgeInsets(
                top: routeMapPadding, left: routeMapPadding,
                bottom: routeMapPadding, right: routeMapPadding
            ),
            isDecorative: true
        )
    }

    /// 样例没有给地图高度（那里是小方块）；140pt 在 6.1 寸屏上大约看得到两三条街。
    private static var routeMapHeight: CGFloat { 140 }
    /// 路线与地图边缘至少留的距离。起点 / 终点标注的图钉有 20pt 左右高，留得比它多一点。
    static var routeMapPadding: CGFloat { 24 }

    /// 让整条路线落在 `size` 减去四边 `padding` 的框里的最大缩放级别。
    ///
    /// 高德与常见网络地图同一套墨卡托分级：z 级下每个点代表 `156543.03 × cos(纬度) / 2^z` 米。
    /// 南北、东西分别算出放得下的级别取较小的那个；结果夹在 3–18 级（18 级已经看得到楼栋）。
    static func fittingZoomLevel(_ coordinates: [CLLocationCoordinate2D], in size: CGSize, padding: CGFloat) -> CGFloat {
        let lats = coordinates.map(\.latitude)
        let lngs = coordinates.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(), let minLng = lngs.min(), let maxLng = lngs.max() else {
            return maximumRouteZoom
        }
        let metresPerDegree = 111_320.0
        let cosLat = cos((minLat + maxLat) / 2 * .pi / 180)
        let spanNorthSouth = (maxLat - minLat) * metresPerDegree
        let spanEastWest = (maxLng - minLng) * metresPerDegree * cosLat
        let usableWidth = max(1, Double(size.width - 2 * padding))
        let usableHeight = max(1, Double(size.height - 2 * padding))
        func zoom(span: Double, points: Double) -> Double {
            span > 0 ? log2(156_543.03 * cosLat * points / span) : Double(maximumRouteZoom)
        }
        let fitted = min(zoom(span: spanEastWest, points: usableWidth), zoom(span: spanNorthSouth, points: usableHeight))
        return CGFloat(min(Double(maximumRouteZoom), max(3, fitted)))
    }

    private static var maximumRouteZoom: CGFloat { 18 }

    /// 外框中心。缩放级别由 `fittingZoomLevel` 按同一个外框算，两者合起来整条路线居中落在框里。
    static func center(of coordinates: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D {
        let lats = coordinates.map(\.latitude)
        let lngs = coordinates.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(), let minLng = lngs.min(), let maxLng = lngs.max() else {
            return CLLocationCoordinate2D()
        }
        return CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2)
    }

    private func recentMessage(_ text: String, identifier: String) -> some View {
        VolunteerSecondaryCard {
            Text(text)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(VolunteerProfileCopy.recentSectionTitle)。\(text)")
        .accessibilityIdentifier(identifier)
    }
}
