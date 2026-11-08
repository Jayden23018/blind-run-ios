import CoreLocation
import SwiftUI

// 两端跑后详情页共用的外壳与组件（#857 候选 3，#879）。两页只交头部和小节。
// 外壳不画任何新东西：背景、导航栏、标签栏、边距都照搬原来两页逐字相同的写法。

// MARK: - 页面外壳

/// 背景、导航栏（标题只给读屏和下一页的返回键）、藏标签栏、加载中 / 失败（`RemoteContent`）、重试任务。
/// 页面自己挂 `accessibilityIdentifier`：外壳最后一层是 `children: .contain`，挂上去不会覆盖子元素
/// （记忆 accessibility-identifier-overwrites-children）。
struct RunRecordDetailPage<Loaded: View>: View {
    @ObservedObject var viewModel: RunRecordViewModel
    let navigationTitle: String
    @ViewBuilder let loaded: (RunRecordResponse) -> Loaded

    var body: some View {
        // 加载中与失败只是一小块，放在页顶并留边距；记录读到后整页交给 `loaded`。
        RemoteContent(
            viewModel.phase,
            loadingLabel: "正在加载跑步记录",
            failureIdentifier: "runRecordRetry",
            retry: { viewModel.startRetry() }
        ) { record in
            loaded(record)
        }
        .padding(viewModel.phase.value == nil ? 20 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppColors.Flow.page.ignoresSafeArea())
        // 屏幕上不显示标题，大标题在地图下沿的头部里（照健身）。
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("").accessibilityHidden(true)
            }
        }
        // 二级页藏标签栏：悬浮胶囊会盖住最后一行（记忆 tab-bar-clips-the-last-line-of-secondary-pages）。
        // 两页都是 push 进来的，返回箭头一直在。
        .toolbar(.hidden, for: .tabBar)
        .accessibilityElement(children: .contain)
        // `.task` 那条随页面取消；「重试」起的那条要在这里停，否则还在 GENERATING 就会一直轮询。
        .onDisappear { viewModel.cancelRetry() }
    }
}

/// 没有地图（或跑者端 VoiceOver 开着）时：头部在页顶，下面是小节，整页一起滚。
/// 有地图时用 `RunRecordMapScrollPage`（`RunRecordFitnessMap.swift`）。
struct RunRecordPlainScrollPage<Header: View, Content: View>: View {
    @ViewBuilder let header: Header
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                content
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    // 滚到底时最后一行别贴着 Home 条。
                    .padding(.bottom, 32)
            }
            .readableContentColumn()
        }
    }
}

// MARK: 状态（两个角色的详情页共用，HANDOFF 6.4）
// 页面级的加载中 / 失败走 `RemoteContent`（#863）。

/// 生成中 / 失败 / 不认识的状态 / 没有路线。READY 且有地图时什么都不画。
struct RunRecordStatusNotice: View {
    let status: RunRecordStatus
    let hasMap: Bool
    let retry: () -> Void

    var body: some View {
        switch status {
        case .generating:
            HStack(spacing: 12) {
                ProgressView()
                Text("记录正在生成，大约 1 分钟后可以查看")
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textPrimary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("runRecordGenerating")
        case .failed, .unknown:
            // 和页面级失败同一套：会念出来（#863）。
            IncentiveFailureSection(
                message: status == .failed ? "记录生成失败。" : "这条记录暂时无法显示。",
                retryTitle: "重试",
                identifier: "runRecordRetry",
                retry: retry
            )
        case .ready, .insufficientTrack:
            if !hasMap {
                Text("这次没有记录到完整路线")
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textSecondary)
                    .accessibilityIdentifier("runRecordNoRoute")
            }
        }
    }
}


// MARK: - Route Map

/// 描边 + 配速线 + 公里标记 + 起终点 + 休息点 + 高亮那一公里。整张图对读屏是装饰（描述挂在页面上）。
/// 两端详情页固定在背后的地图（`RunRecordMapScrollPage`）与跑者端「路线」一节都用它，跑者端 `highlight` 传 nil。
/// 底图降饱和（#823 第 10 条）；配速图例挪到「配速」卡里（左上角现在是返回键）。
struct RunRecordRouteMap: View {
    let geometry: RunRouteGeometry
    let record: RunRecordResponse
    let highlight: VolunteerRunRecordContent.SplitRow?
    /// 路线的取景框：四边让开返回键、右上圆钮、头部（#823 第 11 条）。
    let edgePadding: UIEdgeInsets

    var body: some View {
        MapViewWrapper(
            centerCoordinate: center,
            showsUserLocation: false,
            annotations: annotations,
            polylines: polylines,
            tracksUserLocation: false,
            animatesCenterChanges: false,
            fitEdgePadding: edgePadding,
            isDecorative: true,
            mutedBasemap: true
        )
    }

    private var center: CLLocationCoordinate2D {
        let lats = geometry.coordinates.map(\.latitude)
        let lngs = geometry.coordinates.map(\.longitude)
        return CLLocationCoordinate2D(
            latitude: ((lats.min() ?? 0) + (lats.max() ?? 0)) / 2,
            longitude: ((lngs.min() ?? 0) + (lngs.max() ?? 0)) / 2
        )
    }

    private var polylines: [MapPolylineItem] {
        // 没有配速采样时整条画成「快」那一档的单色。
        let noPace: (indexes: [Int], fractions: [Double]) = ([], [0])
        let pace = RunPaceScale(samples: record.paceSamples).map { geometry.paceStyle(samples: record.paceSamples, scale: $0) } ?? noPace
        var items = [MapPolylineItem(id: "run-outline", coordinates: geometry.coordinates, isPrimary: true, routeStyle: .outline)]
        if let highlight {
            items.append(MapPolylineItem(id: "run-highlight", coordinates: geometry.segment(index: highlight.index), routeStyle: .highlight))
        }
        items.append(MapPolylineItem(
            id: "run-pace",
            coordinates: geometry.coordinates,
            routeStyle: .pace(indexes: pace.indexes, fractions: pace.fractions)
        ))
        return items
    }

    private var annotations: [MapAnnotationItem] {
        var items: [MapAnnotationItem] = []
        // 起点绿点、终点红点照健身（#823 第 10 条）；重合时红点压在绿点上，两个都露一半。
        // 「起点和终点在不在同一处」读屏从地图描述 / 路线描述里听到。
        if let first = geometry.coordinates.first, let last = geometry.coordinates.last {
            items.append(MapAnnotationItem(id: "run-start", coordinate: first, title: nil, subtitle: nil, kind: .runEndpoint(isStart: true, compact: false)))
            items.append(MapAnnotationItem(id: "run-end", coordinate: last, title: nil, subtitle: nil, kind: .runEndpoint(isStart: false, compact: false)))
        }
        for marker in geometry.kilometreMarkers {
            items.append(MapAnnotationItem(id: "run-km-\(marker.km)", coordinate: marker.coordinate, title: nil, subtitle: nil, kind: .runKilometre(marker.km)))
        }
        for (offset, stop) in record.stops.enumerated() {
            guard let lat = stop.lat, let lng = stop.lng else { continue }
            items.append(MapAnnotationItem(
                id: "run-rest-\(offset)",
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                title: nil,
                subtitle: nil,
                kind: .runRest("休息 \(RunRecordText.clock(stop.durationSec))")
            ))
        }
        if let highlight {
            let segment = geometry.segment(index: highlight.index)
            if !segment.isEmpty {
                items.append(MapAnnotationItem(
                    id: "run-bubble",
                    coordinate: segment[segment.count / 2],
                    title: nil,
                    subtitle: nil,
                    kind: .runBubble(highlight.bubbleText)
                ))
            }
        }
        return items
    }
}
