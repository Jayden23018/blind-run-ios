import CoreLocation
import MAMapKit
import SwiftUI
import UIKit

// MARK: - Map Annotation Item

/// 地图标注数据模型
enum MapAnnotationKind: Equatable, Sendable {
    case orderStart
    case currentLocation
    case peer
    case generic
    /// 历史轨迹的两端。与 `orderStart` 分开：那个标的是订单**约定**的出发地，
    /// 这两个标的是实际**跑出来**的第一个和最后一个轨迹点，两者可以差出几百米。
    case routeStart
    case routeEnd
    /// 星火页的一颗星。坐标是片区内按 `cell.id` 确定性散开的**视觉位置**，不是任何人的位置
    /// （`XinghuoSnapshot.sparks`）。志愿者 / 跑者靠形状区分（四角星 / 带环的圆点），
    /// 不依赖颜色 —— 低视力与色弱用户同样分得开。
    case xinghuoSpark(XinghuoSpark)
    /// 星火页的「你」：三圈扩散环 + 「你」气泡。
    case xinghuoSelf(isVolunteer: Bool)
    /// 跑后详情（阶段 4）的自绘标注，图形在 `RunRouteGlyph`。文字就是画在图上的那几个字。
    case runKilometre(Int)
    case runLabel(String)
    case runRest(String)
    case runBubble(String)
}

struct MapAnnotationItem: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let subtitle: String?
    var kind: MapAnnotationKind = .orderStart
}

struct MapPolylineItem: Identifiable {
    let id: String
    let coordinates: [CLLocationCoordinate2D]
    var isPrimary = false
    /// 星火页「我的足迹」：画成暖金光带（光晕 + 亮芯 + 流动光点），与订单轨迹的蓝色主线区分。
    var isFootprint = false
    /// 跑后详情的路线分层；nil 走上面两个旧开关。
    var routeStyle: RouteLineStyle?

    var signature: String {
        coordinates.map { String(format: "%.6f,%.6f", $0.latitude, $0.longitude) }.joined(separator: ";")
            + (routeStyle.map { "|\($0)" } ?? "")
    }
}

/// 跑后详情的三层路线（`docs/research/amap-gradient-polyline-and-outline-20260924.md`）。
/// 高德折线**没有描边属性**，描边就是垫在下面的一条更宽的线。
enum RouteLineStyle: Equatable {
    /// 近黑 `#1C1C1E`，亮暗同值：D8 三档配速色压它都 ≥ 3.81:1，压白色的「中」「慢」只有 2.61 / 1.88（负责人 2026-09-24 拍板）。
    case outline
    /// `indexes` 即 `MAMultiPolyline.drawStyleIndexes`；`fractions` 比它多一个，0 = 快、1 = 慢。
    case pace(indexes: [Int], fractions: [Double])
    /// 点分段行时那一公里底下的一条宽黄带，夹在描边和配速线之间。
    case highlight
}

// MARK: - AMap Container

/// 高德地图 UIViewRepresentable 桥接组件。
/// 将 MAMapView 嵌入 SwiftUI 视图层级，支持用户位置、标注和缩放控制。
struct AMapContainer: UIViewRepresentable {

    let centerCoordinate: CLLocationCoordinate2D
    var showsUserLocation: Bool = true
    var annotations: [MapAnnotationItem] = []
    var polylines: [MapPolylineItem] = []
    var zoomLevel: CGFloat = 15.0
    var recenterToken: Int = 0
    var showsCompass: Bool = false
    var screenAnchor: CGPoint = CGPoint(x: 0.5, y: 0.5)
    var tracksUserLocation: Bool = true
    var animatesCenterChanges: Bool = true
    /// 星火页的夜空底图：关掉路名 / 店铺 / 楼块，再压一层深蓝把路压淡。只有星火页打开。
    var nightSky: Bool = false
    /// `true`（默认）：每次刷新都把地图拉回 `centerCoordinate`，用户拖开也会被拽回来。
    /// `false`：只有传入的坐标本身变了、或 `recenterToken` 变了才回中心 —— 星火页要让人自由拖动，
    /// 否则足迹加载完、开关一拨，地图就「弹」回原处，拖了等于白拖。
    var snapsBackToCenter: Bool = true
    /// 主路线适配视野时四周留的边。跑后详情用它把路线挤到底部卡片上方。
    var fitEdgePadding = UIEdgeInsets(top: 32, left: 24, bottom: 32, right: 24)

    func makeUIView(context: Context) -> AMapHostView {
        let mapView = MAMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = showsUserLocation
        mapView.userTrackingMode = desiredUserTrackingMode
        mapView.setZoomLevel(zoomLevel, animated: false)
        mapView.screenAnchor = screenAnchor
        mapView.setCenter(centerCoordinate, animated: false)
        context.coordinator.lastRequestedCenter = centerCoordinate
        mapView.showsCompass = showsCompass
        mapView.showsScale = !nightSky
        // 跟随系统明暗（design-direction §2 的裁决），全 App 的地图都走这里。
        // 星火页在外面把环境锁成 `.dark`，于是同一条路径给它 `standardNight`。
        let isDark = context.environment.colorScheme == .dark
        context.coordinator.isDark = isDark
        mapView.mapType = Self.mapType(isDark: isDark)
        context.coordinator.animates = !context.environment.accessibilityReduceMotion
        // AidRun updates peer/order markers at multi-second cadence and does not
        // perform in-app turn-by-turn navigation. A 10 fps ceiling is sufficient
        // for panning while preventing an idle home map from driving the main
        // run loop at 60 fps. Default mode also yields rendering while a parent
        // ScrollView is actively tracking a vertical gesture.
        // 星火页例外：拖地图是那一页的主要交互，10 fps 拖起来一顿一顿的。
        // ponytail: 30 是真机前的起始值，跟手程度不够再往上调。
        mapView.maxRenderFrame = nightSky ? 30 : 10
        mapView.isAllowDecreaseFrame = true
        mapView.runLoopMode = .default
        if nightSky {
            applyNightSky(on: mapView, coordinator: context.coordinator)
        }
        // MAMapView continuously mutates a large UIKit subview/accessibility tree
        // while rendering. Exposing those implementation details through a
        // UIViewRepresentable makes SwiftUI rebuild accessibility attributes on
        // every map frame. SwiftUI supplies one stable summary element below.
        mapView.isAccessibilityElement = false
        mapView.accessibilityElementsHidden = true
        return AMapHostView(mapView: mapView)
    }

    func updateUIView(_ hostView: AMapHostView, context: Context) {
        let mapView = hostView.mapView
        // 更新用户位置显示
        if mapView.showsUserLocation != showsUserLocation {
            mapView.showsUserLocation = showsUserLocation
        }
        if mapView.userTrackingMode != desiredUserTrackingMode {
            mapView.userTrackingMode = desiredUserTrackingMode
        }

        if mapView.showsCompass != showsCompass {
            mapView.showsCompass = showsCompass
        }

        let isDark = context.environment.colorScheme == .dark
        if context.coordinator.isDark != isDark {
            context.coordinator.isDark = isDark
            mapView.mapType = Self.mapType(isDark: isDark)
            // 跑后路线的配速色亮暗不同值：三层一起删，由下面的 syncPolylines 按数组顺序、按新配色加回，
            // 叠放顺序才不会乱。
            for (id, entry) in context.coordinator.polylinesByID where entry.routeStyle != nil {
                context.coordinator.remove(entry, from: mapView)
                context.coordinator.polylinesByID.removeValue(forKey: id)
            }
        }

        // 「减弱动态效果」可以在页面开着的时候切换：屏幕上的星、「你」和足迹光点当场跟着换。
        let animates = !context.environment.accessibilityReduceMotion
        if context.coordinator.animates != animates {
            context.coordinator.animates = animates
            context.coordinator.reconfigureXinghuoViews(on: mapView)
        }

        let screenAnchorDidChange =
            abs(context.coordinator.lastScreenAnchor.x - screenAnchor.x) > 0.001 ||
            abs(context.coordinator.lastScreenAnchor.y - screenAnchor.y) > 0.001
        if screenAnchorDidChange {
            mapView.screenAnchor = screenAnchor
            context.coordinator.lastScreenAnchor = screenAnchor
        }

        // 更新地图中心（仅在坐标变化超过阈值时移动，避免频繁跳动）。
        // recenterToken 变化时强制回到传入坐标，用于“回到当前位置”。
        // `snapsBackToCenter == false` 时比的是「上次要求的中心」而不是「地图现在的中心」——
        // 后者在用户拖动之后必然对不上，于是每次刷新都会把人拽回去。
        let currentCenter = mapView.centerCoordinate
        let lastRequested = context.coordinator.lastRequestedCenter
        let threshold: Double = 0.0001
        let requestMoved =
            abs(lastRequested.latitude - centerCoordinate.latitude) > threshold ||
            abs(lastRequested.longitude - centerCoordinate.longitude) > threshold
        let drifted = snapsBackToCenter && (
            abs(currentCenter.latitude - centerCoordinate.latitude) > threshold ||
            abs(currentCenter.longitude - centerCoordinate.longitude) > threshold
        )
        if context.coordinator.lastRecenterToken != recenterToken ||
           screenAnchorDidChange ||
           requestMoved ||
           drifted {
            mapView.setCenter(centerCoordinate, animated: animatesCenterChanges)
            context.coordinator.lastRecenterToken = recenterToken
        }
        context.coordinator.lastRequestedCenter = centerCoordinate

        // 同步标注
        if syncAnnotations(on: mapView, coordinator: context.coordinator) {
            ClientFlowDiagnostics.record(event: "applied", operation: "map-annotations")
        }
        syncPolylines(on: mapView, coordinator: context.coordinator)
    }

    static func dismantleUIView(_ hostView: AMapHostView, coordinator: Coordinator) {
        hostView.mapView.delegate = nil
        hostView.mapView.showsUserLocation = false
        coordinator.styledAnnotationsByID.removeAll()
        for entry in coordinator.polylinesByID.values {
            coordinator.remove(entry, from: hostView.mapView)
        }
        coordinator.polylinesByID.removeAll()
        coordinator.lastFittedPrimarySignature = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Private

    private var desiredUserTrackingMode: MAUserTrackingMode {
        showsUserLocation && tracksUserLocation ? .follow : .none
    }

    static func mapType(isDark: Bool) -> MAMapType {
        isDark ? .standardNight : .standard
    }

    /// 星火页的夜空底图。原型是 canvas 画的假城市（深蓝底、极淡的路、没有一个字），
    /// 高德只能逼近：关掉底图文字与楼块，再在道路之上、星星之下铺一层深蓝把路压淡。
    /// 标注是 GL 之上的 UIView，所以这层压不到星星。
    // ponytail: 控制台自定义样式（`MAMapCustomStyleOptions`）能做得更干净，要负责人去高德控制台建，
    // 拿到 styleId 或样式文件后在这里接；在那之前不编造 styleId。
    private func applyNightSky(on mapView: MAMapView, coordinator: Coordinator) {
        mapView.isShowsLabels = false
        mapView.isShowsBuildings = false
        mapView.touchPOIEnabled = false
        mapView.isRotateCameraEnabled = false
        // 覆盖中心 ±1°（约 100 km）：城市级页面拖不出这个范围。
        let c = centerCoordinate
        var corners = [
            CLLocationCoordinate2D(latitude: c.latitude - 1, longitude: c.longitude - 1),
            CLLocationCoordinate2D(latitude: c.latitude - 1, longitude: c.longitude + 1),
            CLLocationCoordinate2D(latitude: c.latitude + 1, longitude: c.longitude + 1),
            CLLocationCoordinate2D(latitude: c.latitude + 1, longitude: c.longitude - 1),
        ]
        guard let wash = MAPolygon(coordinates: &corners, count: UInt(corners.count)) else { return }
        coordinator.nightWash = wash
        mapView.add(wash, level: .aboveRoads)
    }

    private func syncAnnotations(on mapView: MAMapView, coordinator: Coordinator) -> Bool {
        if coordinator.sparkEpoch == nil, annotations.contains(where: \.kind.isXinghuoSpark) {
            // 点亮顺序从这一刻起算。拖动后新进屏幕的星按这个时刻判断「早就亮过了」，不会再闪一次。
            coordinator.sparkEpoch = CACurrentMediaTime()
        }
        var didChange = false
        let incomingIDs = Set(annotations.map(\.id))
        let removedIDs = coordinator.styledAnnotationsByID.keys.filter { !incomingIDs.contains($0) }
        for id in removedIDs {
            if let annotation = coordinator.styledAnnotationsByID.removeValue(forKey: id) {
                mapView.removeAnnotation(annotation)
                didChange = true
            }
        }

        for item in annotations {
            if let existing = coordinator.styledAnnotationsByID[item.id] {
                didChange = existing.update(with: item) || didChange
            } else {
                let annotation = StyledMapPointAnnotation(item: item)
                coordinator.styledAnnotationsByID[item.id] = annotation
                mapView.addAnnotation(annotation)
                didChange = true
            }
        }
        return didChange
    }

    private func syncPolylines(on mapView: MAMapView, coordinator: Coordinator) {
        let drawablePolylines = polylines.filter { $0.coordinates.count >= 2 }
        let incomingIDs = Set(drawablePolylines.map(\.id))
        for id in coordinator.polylinesByID.keys.filter({ !incomingIDs.contains($0) }) {
            if let removed = coordinator.polylinesByID.removeValue(forKey: id) {
                coordinator.remove(removed, from: mapView)
                if removed.isPrimary {
                    coordinator.lastFittedPrimarySignature = nil
                }
            }
        }

        for item in drawablePolylines {
            if coordinator.polylinesByID[item.id]?.signature == item.signature { continue }
            if let previous = coordinator.polylinesByID.removeValue(forKey: item.id) {
                coordinator.remove(previous, from: mapView)
            }
            var coordinates = item.coordinates
            let built: MAPolyline?
            if case .pace(let indexes, _) = item.routeStyle {
                built = MAMultiPolyline(
                    coordinates: &coordinates,
                    count: UInt(coordinates.count),
                    drawStyleIndexes: indexes.map { NSNumber(value: $0) }
                )
            } else {
                built = MAPolyline(coordinates: &coordinates, count: UInt(coordinates.count))
            }
            guard let overlay = built else { continue }
            let entry = PolylineEntry(
                overlay: overlay,
                coordinates: item.coordinates,
                signature: item.signature,
                isPrimary: item.isPrimary,
                isFootprint: item.isFootprint,
                routeStyle: item.routeStyle
            )
            coordinator.polylinesByID[item.id] = entry
            if item.isFootprint {
                // 光带 = 宽而淡的光晕压在下面 + 窄而亮的芯（原型「mine」那一档）。
                // 高德一条线只有一种描边，所以画两条。
                entry.glow = MAPolyline(coordinates: &coordinates, count: UInt(coordinates.count))
                entry.glow.map { mapView.add($0) }
            }
            // 高亮带是点分段行时才加的，那时配速线早已在图上 —— 直接 add 会盖住它。
            if item.routeStyle == .highlight,
               let pace = coordinator.polylinesByID.values.first(where: { $0.routeStyle?.isPace == true })?.overlay {
                mapView.insert(overlay, below: pace)
            } else {
                mapView.add(overlay)
            }
            if item.isFootprint, coordinator.animates {
                coordinator.startComet(on: entry, mapView: mapView)
            }

            if item.isPrimary, coordinator.lastFittedPrimarySignature != item.signature {
                mapView.setVisibleMapRect(
                    overlay.boundingMapRect,
                    edgePadding: fitEdgePadding,
                    animated: false
                )
                coordinator.lastFittedPrimarySignature = item.signature
            }
        }
    }

    final class StyledMapPointAnnotation: MAPointAnnotation {
        let id: String
        var kind: MapAnnotationKind

        init(item: MapAnnotationItem) {
            self.id = item.id
            self.kind = item.kind
            super.init()
            update(with: item)
        }

        @discardableResult
        func update(with item: MapAnnotationItem) -> Bool {
            let changed =
                kind != item.kind ||
                abs(coordinate.latitude - item.coordinate.latitude) > 0.0000001 ||
                abs(coordinate.longitude - item.coordinate.longitude) > 0.0000001 ||
                title != item.title ||
                subtitle != item.subtitle
            guard changed else { return false }
            kind = item.kind
            coordinate = item.coordinate
            title = item.title
            subtitle = item.subtitle
            return true
        }
    }

    // MARK: - Coordinator

    /// 一条线在地图上的全部东西。足迹多一条光晕线和一颗沿线流动的光点。
    final class PolylineEntry {
        let overlay: MAPolyline
        let coordinates: [CLLocationCoordinate2D]
        let signature: String
        let isPrimary: Bool
        let isFootprint: Bool
        let routeStyle: RouteLineStyle?
        var glow: MAPolyline?
        var comet: XinghuoCometAnnotation?

        init(
            overlay: MAPolyline,
            coordinates: [CLLocationCoordinate2D],
            signature: String,
            isPrimary: Bool,
            isFootprint: Bool,
            routeStyle: RouteLineStyle? = nil
        ) {
            self.overlay = overlay
            self.coordinates = coordinates
            self.signature = signature
            self.isPrimary = isPrimary
            self.isFootprint = isFootprint
            self.routeStyle = routeStyle
        }
    }

    final class Coordinator: NSObject, MAMapViewDelegate {
        var lastRecenterToken = 0
        var lastRequestedCenter = CLLocationCoordinate2D()
        var lastScreenAnchor = CGPoint(x: 0.5, y: 0.5)
        var styledAnnotationsByID: [String: StyledMapPointAnnotation] = [:]
        var polylinesByID: [String: PolylineEntry] = [:]
        var lastFittedPrimarySignature: String?
        var isDark = false
        /// `false` = 系统「减弱动态效果」打开：星不闪、不按距离点亮、足迹上没有流动光点。
        var animates = true
        /// 星火页第一批星加进地图的时刻，点亮延迟从这里起算。
        var sparkEpoch: CFTimeInterval?
        var nightWash: MAPolygon?

        func remove(_ entry: PolylineEntry, from mapView: MAMapView) {
            mapView.remove(entry.overlay)
            entry.glow.map { mapView.remove($0) }
            stopComet(on: entry, mapView: mapView)
        }

        // MARK: 足迹上的流动光点

        /// 一颗光点沿足迹从头走到尾，走完再从头开始。速度按长度定，长短路线看上去一样快。
        func startComet(on entry: PolylineEntry, mapView: MAMapView) {
            guard entry.comet == nil, entry.coordinates.count >= 2 else { return }
            let comet = XinghuoCometAnnotation()
            comet.coordinate = entry.coordinates[0]
            entry.comet = comet
            mapView.addAnnotation(comet)
            runComet(comet, on: entry)
        }

        func stopComet(on entry: PolylineEntry, mapView: MAMapView) {
            guard let comet = entry.comet else { return }
            entry.comet = nil
            comet.allMoveAnimations()?.forEach { $0.cancel() }
            mapView.removeAnnotation(comet)
        }

        private func runComet(_ comet: XinghuoCometAnnotation, on entry: PolylineEntry) {
            var coordinates = entry.coordinates
            comet.coordinate = coordinates[0]
            let meters = zip(coordinates, coordinates.dropFirst()).reduce(0.0) { sum, pair in
                sum + MAMetersBetweenMapPoints(MAMapPointForCoordinate(pair.0), MAMapPointForCoordinate(pair.1))
            }
            // ponytail: 400 m/s ≈ 2.6 km 的环线 6.5 秒走一圈，真机看着太快 / 太慢就改这个数。
            let duration = CGFloat(max(3, meters / 400))
            coordinates.withUnsafeMutableBufferPointer { buffer in
                _ = comet.addMoveAnimation(
                    withKeyCoordinates: buffer.baseAddress,
                    count: UInt(buffer.count),
                    withDuration: duration,
                    withName: nil
                ) { [weak self, weak comet, weak entry] finished in
                    // 被取消（关开关、减弱动态效果、离开页面）时 finished 为 false，不再续。
                    guard finished, let self, let comet, let entry, entry.comet === comet else { return }
                    self.runComet(comet, on: entry)
                }
            }
        }

        /// 「减弱动态效果」切换时：屏幕上的星与「你」重新配置，光点加上或撤掉。
        func reconfigureXinghuoViews(on mapView: MAMapView) {
            for annotation in styledAnnotationsByID.values {
                guard let view = mapView.view(for: annotation) else { continue }
                configure(view, for: annotation.kind)
            }
            for entry in polylinesByID.values where entry.isFootprint {
                if animates {
                    startComet(on: entry, mapView: mapView)
                } else {
                    stopComet(on: entry, mapView: mapView)
                }
            }
        }

        private func configure(_ view: MAAnnotationView, for kind: MapAnnotationKind) {
            switch kind {
            case .xinghuoSpark(let spark):
                (view as? XinghuoSparkView)?.configure(spark: spark, animates: animates, epoch: sparkEpoch)
            case .xinghuoSelf(let isVolunteer):
                (view as? XinghuoSelfView)?.configure(isVolunteer: isVolunteer, animates: animates)
            default:
                break
            }
        }

        func mapView(_ mapView: MAMapView!, viewFor annotation: MAAnnotation!) -> MAAnnotationView! {
            // 用户位置使用默认蓝点
            if annotation is MAUserLocation {
                return nil
            }
            if annotation is XinghuoCometAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: XinghuoCometView.reuseID)
                    ?? XinghuoCometView(annotation: annotation, reuseIdentifier: XinghuoCometView.reuseID)
                view?.annotation = annotation
                view?.canShowCallout = false
                return view
            }

            let kind = (annotation as? StyledMapPointAnnotation)?.kind ?? .generic
            if let glyph = RunRouteGlyph.image(for: kind) {
                let reuseID = "RunRoute-\(kind)"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: reuseID)
                    ?? MAAnnotationView(annotation: annotation, reuseIdentifier: reuseID)
                view?.annotation = annotation
                view?.image = glyph.image
                view?.zIndex = glyph.zIndex
                view?.canShowCallout = false
                return view
            }
            let xinghuoView: MAAnnotationView?
            switch kind {
            case .xinghuoSpark:
                xinghuoView = mapView.dequeueReusableAnnotationView(withIdentifier: XinghuoSparkView.reuseID)
                    ?? XinghuoSparkView(annotation: annotation, reuseIdentifier: XinghuoSparkView.reuseID)
            case .xinghuoSelf:
                xinghuoView = mapView.dequeueReusableAnnotationView(withIdentifier: XinghuoSelfView.reuseID)
                    ?? XinghuoSelfView(annotation: annotation, reuseIdentifier: XinghuoSelfView.reuseID)
            default:
                xinghuoView = nil
            }
            if let xinghuoView {
                xinghuoView.annotation = annotation
                xinghuoView.canShowCallout = false
                configure(xinghuoView, for: kind)
                return xinghuoView
            }
            let reuseID = "OrderPin-\(kind)"
            var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: reuseID) as? MAPinAnnotationView
            if annotationView == nil {
                annotationView = MAPinAnnotationView(annotation: annotation, reuseIdentifier: reuseID)
            } else {
                annotationView?.annotation = annotation
            }
            annotationView?.canShowCallout = true
            annotationView?.animatesDrop = false
            annotationView?.pinColor = kind.pinColor
            return annotationView
        }

        func mapView(_ mapView: MAMapView!, rendererFor overlay: MAOverlay!) -> MAOverlayRenderer! {
            if let wash = overlay as? MAPolygon, wash === nightWash {
                let renderer = MAPolygonRenderer(polygon: wash)
                // ponytail: 0.5 是真机前的起始值 —— 路还太显眼就往上调，底图糊成一片就往下调。
                renderer?.fillColor = UIColor(rgb: AppColors.Xinghuo.nightRGB).withAlphaComponent(0.5)
                renderer?.strokeColor = .clear
                renderer?.lineWidth = 0
                return renderer
            }
            guard let polyline = overlay as? MAPolyline else { return nil }
            if let style = polylinesByID.values.first(where: { $0.overlay === polyline })?.routeStyle {
                return RunRouteGlyph.renderer(for: polyline, style: style, isDark: isDark)
            }
            let renderer = MAPolylineRenderer(polyline: polyline)
            if polylinesByID.values.contains(where: { $0.glow === polyline }) {
                renderer?.lineWidth = 9
                renderer?.strokeColor = UIColor(rgb: AppColors.Xinghuo.emberRGB).withAlphaComponent(0.18)
                return renderer
            }
            let entry = polylinesByID.values.first(where: { $0.overlay === polyline })
            if entry?.isFootprint == true {
                renderer?.lineWidth = 2.4
                renderer?.strokeColor = UIColor(rgb: AppColors.Xinghuo.starCoreRGB).withAlphaComponent(0.8)
                return renderer
            }
            let isPrimary = entry?.isPrimary == true
            renderer?.lineWidth = isPrimary ? 7 : 4
            renderer?.strokeColor = isPrimary ? UIColor.systemBlue : UIColor.systemGray
            return renderer
        }
    }
}

/// SwiftUI owns this stable shell, while MAMapView performs its continuous
/// renderer/layout work as an internal UIKit child. Returning MAMapView itself
/// allows those internal invalidations to propagate to the representable root
/// and can keep AttributeGraph evaluating the entire home page.
final class AMapHostView: UIView {
    let mapView: MAMapView

    init(mapView: MAMapView) {
        self.mapView = mapView
        super.init(frame: .zero)
        clipsToBounds = true
        mapView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mapView)
        NSLayoutConstraint.activate([
            mapView.leadingAnchor.constraint(equalTo: leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: trailingAnchor),
            mapView.topAnchor.constraint(equalTo: topAnchor),
            mapView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
    }
}

private extension MapAnnotationKind {
    var pinColor: MAPinAnnotationColor {
        switch self {
        case .orderStart:
            return .red
        case .currentLocation:
            return .green
        case .peer:
            return .purple
        case .generic:
            return .purple
        // 绿起红终是跑步类产品的通用约定，不自创配色。
        case .routeStart:
            return .green
        case .routeEnd:
            return .red
        // 星火页的标注走自己的视图（`XinghuoSparkView` / `XinghuoSelfView`），不会落到大头针上。
        case .xinghuoSpark, .xinghuoSelf:
            return .purple
        // 跑后详情的标注走 `RunRouteGlyph` 的自绘图片。
        case .runKilometre, .runLabel, .runRest, .runBubble:
            return .purple
        }
    }
}

extension MapAnnotationKind {
    var isXinghuoSpark: Bool {
        if case .xinghuoSpark = self { return true }
        return false
    }
}

// MARK: - 星火页标注

/// 星火页标注共用的画材。形状与光晕照负责人给的 HTML 原型（`glow()` / `sparkle()` / `drawAgent()`），
/// 颜色取 `AppColors.Xinghuo`，不另抄色值。
enum XinghuoGlyph {
    /// 星的基准半径（pt），约等于原型 `starSize()` 在初始缩放下的值；每颗再乘自己的 `scale`。
    static let baseRadius: CGFloat = 5

    static let volunteerGlow = glow(AppColors.Xinghuo.emberRGB)
    static let runnerGlow = glow(AppColors.Xinghuo.moonRGB)
    /// 点亮那一下的白色闪光（原型 `GL.white`）。
    static let flareGlow = glow(0xFFF4E2)

    /// 放射状光晕，渐变停点照原型 `glow()`：芯 1 → 10% 处 0.65 → 32% 处 0.18 → 边缘 0。
    static func glow(_ rgb: UInt32) -> CGImage? {
        let side: CGFloat = 128
        let color = UIColor(rgb: rgb)
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { context in
            let colors = [1, 0.65, 0.18, 0].map { color.withAlphaComponent($0).cgColor } as CFArray
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 0.1, 0.32, 1]
            ) else { return }
            let center = CGPoint(x: side / 2, y: side / 2)
            context.cgContext.drawRadialGradient(
                gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: side / 2, options: []
            )
        }.cgImage
    }

    /// 四角星：四个尖，腰用二次曲线收进去（原型 `sparkle()`）。
    static func sparklePath(radius: CGFloat, rotation: CGFloat, center: CGPoint) -> UIBezierPath {
        let path = UIBezierPath()
        path.move(to: point(center, radius, rotation))
        for i in 1...4 {
            let angle = rotation + CGFloat(i) * .pi / 2
            path.addQuadCurve(to: point(center, radius, angle), controlPoint: point(center, radius * 0.2, angle - .pi / 4))
        }
        path.close()
        return path
    }

    /// 跑者：实心小圆点 + 一圈细环（原型 `drawAgent` 的 else 分支）。
    static func runnerDotPath(radius: CGFloat, center: CGPoint) -> UIBezierPath {
        UIBezierPath(ovalIn: CGRect(x: center.x - radius * 0.5, y: center.y - radius * 0.5, width: radius, height: radius))
    }

    static func runnerRingPath(radius: CGFloat, center: CGPoint) -> UIBezierPath {
        UIBezierPath(ovalIn: CGRect(x: center.x - radius * 1.05, y: center.y - radius * 1.05, width: radius * 2.1, height: radius * 2.1))
    }

    private static func point(_ center: CGPoint, _ radius: CGFloat, _ angle: CGFloat) -> CGPoint {
        CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
    }

    /// 画一颗星的芯（光晕另算）：志愿者是四角星，跑者是圆点 + 环。
    static func drawCore(isVolunteer: Bool, radius: CGFloat, rotation: CGFloat, center: CGPoint,
                         core: CAShapeLayer, ring: CAShapeLayer) {
        if isVolunteer {
            core.path = sparklePath(radius: radius * 1.1, rotation: rotation, center: center).cgPath
            core.fillColor = UIColor(rgb: AppColors.Xinghuo.starCoreRGB).cgColor
            ring.path = nil
        } else {
            core.path = runnerDotPath(radius: radius, center: center).cgPath
            core.fillColor = UIColor(rgb: AppColors.Xinghuo.runnerCoreRGB).cgColor
            ring.path = runnerRingPath(radius: radius, center: center).cgPath
            ring.fillColor = nil
            ring.lineWidth = 1.3
            ring.strokeColor = UIColor(rgb: AppColors.Xinghuo.moonRGB).withAlphaComponent(0.8).cgColor
        }
    }
}

/// 星火页的一颗星。动效全走 Core Animation —— 在渲染服务里跑，不占主线程，
/// 也不受地图 `maxRenderFrame` 的限制。
///
/// 「减弱动态效果」打开时（`animates == false`）一个动画都不加：星直接以静止的亮度出现，
/// 与原型 `prefers-reduced-motion` 分支一致。
final class XinghuoSparkView: MAAnnotationView {
    static let reuseID = "XinghuoSpark"
    private static let side: CGFloat = 64

    /// 光晕和芯装在同一层里，点亮时整层一起淡入。
    private let body = CALayer()
    private let glowLayer = CALayer()
    private let coreLayer = CAShapeLayer()
    private let ringLayer = CAShapeLayer()
    private let flareLayer = CALayer()

    override init!(annotation: MAAnnotation!, reuseIdentifier: String!) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        bounds = CGRect(x: 0, y: 0, width: Self.side, height: Self.side)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        body.frame = bounds
        coreLayer.frame = bounds
        ringLayer.frame = bounds
        layer.addSublayer(body)
        body.addSublayer(glowLayer)
        body.addSublayer(ringLayer)
        body.addSublayer(coreLayer)
        flareLayer.contents = XinghuoGlyph.flareGlow
        flareLayer.opacity = 0
        layer.addSublayer(flareLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        stopAnimations()
    }

    /// 现在挂着的动画 key。只给单测看「减弱动态效果时真的一个都没有」。
    var activeAnimationKeys: [String] {
        [body, glowLayer, flareLayer].flatMap { $0.animationKeys() ?? [] }
    }

    func configure(spark: XinghuoSpark, animates: Bool, epoch: CFTimeInterval?) {
        stopAnimations()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let center = CGPoint(x: Self.side / 2, y: Self.side / 2)
        let radius = XinghuoGlyph.baseRadius * CGFloat(spark.scale)
        let isVolunteer = spark.kind == .volunteer
        let glowSide = radius * (isVolunteer ? 7.5 : 6.5)
        glowLayer.frame = CGRect(x: center.x - glowSide / 2, y: center.y - glowSide / 2, width: glowSide, height: glowSide)
        glowLayer.contents = isVolunteer ? XinghuoGlyph.volunteerGlow : XinghuoGlyph.runnerGlow
        glowLayer.opacity = Float(0.9 * spark.brightness)
        XinghuoGlyph.drawCore(
            isVolunteer: isVolunteer, radius: radius, rotation: CGFloat(spark.rotation),
            center: center, core: coreLayer, ring: ringLayer
        )
        let flareSide = radius * 26
        flareLayer.frame = CGRect(x: center.x - flareSide / 2, y: center.y - flareSide / 2, width: flareSide, height: flareSide)

        guard animates else { return }

        // 闪烁：光晕的明暗与大小随正弦起伏（原型 `tw = .72 + .28·sin(…)`），各颗错开相位。
        let period = spark.twinklePeriod
        for (keyPath, from, to) in [
            ("opacity", 0.45 * spark.brightness, 0.9 * spark.brightness),
            ("transform.scale", 0.85, 1.15),
        ] {
            let twinkle = CABasicAnimation(keyPath: keyPath)
            twinkle.fromValue = from
            twinkle.toValue = to
            twinkle.duration = period / 2
            twinkle.autoreverses = true
            twinkle.repeatCount = .infinity
            twinkle.timeOffset = spark.phase * period
            twinkle.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            glowLayer.add(twinkle, forKey: "twinkle-\(keyPath)")
        }

        // 点亮：从「你」开始一圈圈向外。已经过了点亮时刻的（拖动后才进屏幕的）直接显示，不再闪一次。
        guard let epoch else { return }
        let start = epoch + spark.igniteDelay
        guard CACurrentMediaTime() < start + 1.3 else { return }
        let begin = layer.convertTime(start, from: nil)

        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0
        fadeIn.toValue = 1
        fadeIn.duration = 0.5
        fadeIn.beginTime = begin
        fadeIn.fillMode = .backwards
        body.add(fadeIn, forKey: "ignite")

        // 白色闪光：一下放大到很大再迅速收缩淡出，1.3 秒（原型 `ignition flare`）。
        let flareOpacity = CAKeyframeAnimation(keyPath: "opacity")
        flareOpacity.values = [0, 0.9, 0]
        flareOpacity.keyTimes = [0, 0.02, 1]
        let flareScale = CABasicAnimation(keyPath: "transform.scale")
        flareScale.fromValue = 1
        flareScale.toValue = 0.25
        let flare = CAAnimationGroup()
        flare.animations = [flareOpacity, flareScale]
        flare.duration = 1.3
        flare.beginTime = begin
        flare.fillMode = .backwards
        flare.timingFunction = CAMediaTimingFunction(name: .easeOut)
        flareLayer.add(flare, forKey: "ignite-flare")
    }

    private func stopAnimations() {
        body.removeAllAnimations()
        glowLayer.removeAllAnimations()
        flareLayer.removeAllAnimations()
    }
}

/// 星火页的「你」：三圈错开的扩散环 + 一颗稍大的星 + 「你」气泡（原型 `drawMe`）。
/// 「减弱动态效果」时只留一圈静止的环。
final class XinghuoSelfView: MAAnnotationView {
    static let reuseID = "XinghuoSelf"
    private static let side: CGFloat = 132
    private static let ringPeriod: CFTimeInterval = 2.5

    private let rings = (0..<3).map { _ in CAShapeLayer() }
    private let glowLayer = CALayer()
    private let coreLayer = CAShapeLayer()
    private let ringLayer = CAShapeLayer()
    private let bubble = UILabel()

    override init!(annotation: MAAnnotation!, reuseIdentifier: String!) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        bounds = CGRect(x: 0, y: 0, width: Self.side, height: Self.side)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        zIndex = 10
        let center = CGPoint(x: Self.side / 2, y: Self.side / 2)
        for ring in rings {
            ring.frame = bounds
            ring.path = UIBezierPath(arcCenter: center, radius: 60, startAngle: 0, endAngle: 2 * .pi, clockwise: true).cgPath
            ring.fillColor = nil
            ring.lineWidth = 1.5
            layer.addSublayer(ring)
        }
        coreLayer.frame = bounds
        ringLayer.frame = bounds
        layer.addSublayer(glowLayer)
        layer.addSublayer(ringLayer)
        layer.addSublayer(coreLayer)

        bubble.text = "你"
        bubble.font = .systemFont(ofSize: 12, weight: .semibold)
        bubble.textColor = UIColor(rgb: AppColors.Xinghuo.nightRGB)
        bubble.textAlignment = .center
        bubble.backgroundColor = UIColor.white.withAlphaComponent(0.94)
        bubble.layer.cornerRadius = 9
        bubble.layer.masksToBounds = true
        bubble.frame = CGRect(x: center.x - 13, y: center.y - 42, width: 26, height: 19)
        addSubview(bubble)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(isVolunteer: Bool, animates: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let center = CGPoint(x: Self.side / 2, y: Self.side / 2)
        let radius = XinghuoGlyph.baseRadius * 1.45
        let glowSide = radius * 7.5
        glowLayer.frame = CGRect(x: center.x - glowSide / 2, y: center.y - glowSide / 2, width: glowSide, height: glowSide)
        glowLayer.contents = isVolunteer ? XinghuoGlyph.volunteerGlow : XinghuoGlyph.runnerGlow
        XinghuoGlyph.drawCore(
            isVolunteer: isVolunteer, radius: radius, rotation: 0, center: center, core: coreLayer, ring: ringLayer
        )

        let color = UIColor(rgb: isVolunteer ? AppColors.Xinghuo.emberRGB : AppColors.Xinghuo.moonRGB)
        for (index, ring) in rings.enumerated() {
            ring.removeAllAnimations()
            ring.strokeColor = color.cgColor
            if animates {
                ring.transform = CATransform3DIdentity
                ring.opacity = 0
                let scale = CABasicAnimation(keyPath: "transform.scale")
                scale.fromValue = 0.2
                scale.toValue = 1
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 0.55
                fade.toValue = 0
                let pulse = CAAnimationGroup()
                pulse.animations = [scale, fade]
                pulse.duration = Self.ringPeriod
                pulse.repeatCount = .infinity
                pulse.timeOffset = Self.ringPeriod * Double(index) / Double(rings.count)
                ring.add(pulse, forKey: "pulse")
            } else {
                ring.transform = CATransform3DMakeScale(0.4, 0.4, 1)
                ring.opacity = index == 0 ? 0.4 : 0
            }
        }
    }
}

/// 足迹上的流动光点（「光带流动」）。只给 `AMapContainer.Coordinator.startComet` 用。
final class XinghuoCometAnnotation: MAAnimatedAnnotation {}

final class XinghuoCometView: MAAnnotationView {
    static let reuseID = "XinghuoComet"

    override init!(annotation: MAAnnotation!, reuseIdentifier: String!) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        let side: CGFloat = 26
        bounds = CGRect(x: 0, y: 0, width: side, height: side)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        zIndex = 5
        let glow = CALayer()
        glow.frame = bounds
        glow.contents = XinghuoGlyph.volunteerGlow
        layer.addSublayer(glow)
        let core = CAShapeLayer()
        core.path = UIBezierPath(ovalIn: CGRect(x: side / 2 - 2, y: side / 2 - 2, width: 4, height: 4)).cgPath
        core.fillColor = UIColor(rgb: AppColors.Xinghuo.starCoreRGB).cgColor
        layer.addSublayer(core)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Map View Wrapper

private extension View {
    /// 装饰用法**不合成**无障碍元素；其余用法维持原来的 label + hint。
    ///
    /// 分两条路而不是「合成之后再 hidden」，是因为后者实测无效 —— 见
    /// `MapViewWrapper.isDecorative` 的说明。
    @ViewBuilder
    func mapAccessibility(isDecorative: Bool) -> some View {
        if isDecorative {
            accessibilityHidden(true)
        } else {
            accessibilityElement(children: .ignore)
                .accessibilityLabel("地图，显示当前位置和订单地点")
                .accessibilityHint("地图为辅助显示，主要操作请使用下方按钮")
        }
    }
}

/// 显示 AMap；仅在 Key 缺失或 UI 测试显式禁用地图时呈现配置故障降级视图。
struct MapViewWrapper: View {
    let centerCoordinate: CLLocationCoordinate2D
    var showsUserLocation: Bool = true
    var annotations: [MapAnnotationItem] = []
    var polylines: [MapPolylineItem] = []
    var zoomLevel: CGFloat = 15.0
    var recenterToken: Int = 0
    var showsCompass: Bool = false
    var screenAnchor: CGPoint = CGPoint(x: 0.5, y: 0.5)
    var tracksUserLocation: Bool = true
    var animatesCenterChanges: Bool = true
    var fitEdgePadding = UIEdgeInsets(top: 32, left: 24, bottom: 32, right: 24)

    /// 装饰用法：地图是纯背景（不可交互，且同样的信息在别处有文字版），
    /// 读屏用户不该在遍历里碰到它。
    ///
    /// **它必须在这里生效，而不是由调用方在外面加 `.accessibilityHidden(true)`。**
    /// 下面那条 `.accessibilityElement(children: .ignore)` + `.accessibilityLabel` 会
    /// **合成一个新的无障碍元素**，外层的 `accessibilityHidden` 盖不住它 —— 2026-08-22 在真机上
    /// 实测：`BlindRunnerHomeView.mapBackgroundLayer` 明明写着 `.accessibilityHidden(true)`，
    /// 真 key 构建下 `Other 402x200 «地图，显示当前位置和订单地点»` 照样排在
    /// `blindRunnerHomeScrollView` **前面**。
    ///
    /// 2026-08-14 的 `30b0770` 以为这个问题修好了，是因为它只在 `disableMap: true`（占位图）
    /// 路径上验过，而**生产构建走的是真 key 那条**。修法是根本不合成那个元素 ——
    /// 藏不住一个不存在的元素。底层 `MAMapView` 早就设了
    /// `isAccessibilityElement = false` / `accessibilityElementsHidden = true`（见 makeUIView），
    /// 所以不合成就干净了。
    ///
    /// 只影响无障碍树，视觉完全不变。
    var isDecorative: Bool = false
    /// 见 `AMapContainer.nightSky` / `snapsBackToCenter`。只有星火页打开 / 关掉。
    var nightSky: Bool = false
    var snapsBackToCenter: Bool = true

    var body: some View {
        #if DEBUG || DEMO
        if ProcessInfo.processInfo.environment["AIDRUN_UI_TEST_DISABLE_MAP"] == "1" {
            MapPlaceholderView()
                .accessibilityHidden(isDecorative)
        } else if AMapManager.isConfigured {
            AMapContainer(
                centerCoordinate: centerCoordinate,
                showsUserLocation: showsUserLocation,
                annotations: annotations,
                polylines: polylines,
                zoomLevel: zoomLevel,
                recenterToken: recenterToken,
                showsCompass: showsCompass,
                screenAnchor: screenAnchor,
                tracksUserLocation: tracksUserLocation,
                animatesCenterChanges: animatesCenterChanges,
                nightSky: nightSky,
                snapsBackToCenter: snapsBackToCenter,
                fitEdgePadding: fitEdgePadding
            )
            .mapAccessibility(isDecorative: isDecorative)
        } else {
            MapPlaceholderView()
                .accessibilityHidden(isDecorative)
        }
        #else
        if AMapManager.isConfigured {
            AMapContainer(
                centerCoordinate: centerCoordinate,
                showsUserLocation: showsUserLocation,
                annotations: annotations,
                polylines: polylines,
                zoomLevel: zoomLevel,
                recenterToken: recenterToken,
                showsCompass: showsCompass,
                screenAnchor: screenAnchor,
                tracksUserLocation: tracksUserLocation,
                animatesCenterChanges: animatesCenterChanges,
                nightSky: nightSky,
                snapsBackToCenter: snapsBackToCenter,
                fitEdgePadding: fitEdgePadding
            )
            .mapAccessibility(isDecorative: isDecorative)
        } else {
            MapPlaceholderView()
                .accessibilityHidden(isDecorative)
        }
        #endif
    }
}
