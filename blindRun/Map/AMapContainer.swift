import CoreLocation
import MAMapKit
import SwiftUI

// MARK: - Map Annotation Item

/// 地图标注数据模型
struct MapAnnotationItem: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let subtitle: String?
}

// MARK: - AMap Container

/// 高德地图 UIViewRepresentable 桥接组件。
/// 将 MAMapView 嵌入 SwiftUI 视图层级，支持用户位置、标注和缩放控制。
struct AMapContainer: UIViewRepresentable {

    let centerCoordinate: CLLocationCoordinate2D
    var showsUserLocation: Bool = true
    var annotations: [MapAnnotationItem] = []
    var zoomLevel: CGFloat = 15.0
    var recenterToken: Int = 0
    var showsCompass: Bool = true
    var screenAnchor: CGPoint = CGPoint(x: 0.5, y: 0.5)

    func makeUIView(context: Context) -> MAMapView {
        let mapView = MAMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = showsUserLocation
        mapView.userTrackingMode = .follow
        mapView.setZoomLevel(zoomLevel, animated: false)
        mapView.screenAnchor = screenAnchor
        mapView.setCenter(centerCoordinate, animated: false)
        mapView.showsCompass = showsCompass
        mapView.showsScale = true
        return mapView
    }

    func updateUIView(_ mapView: MAMapView, context: Context) {
        // 更新用户位置显示
        if mapView.showsUserLocation != showsUserLocation {
            mapView.showsUserLocation = showsUserLocation
        }

        if mapView.showsCompass != showsCompass {
            mapView.showsCompass = showsCompass
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
        let currentCenter = mapView.centerCoordinate
        let threshold: Double = 0.0001
        if context.coordinator.lastRecenterToken != recenterToken ||
           screenAnchorDidChange ||
           abs(currentCenter.latitude - centerCoordinate.latitude) > threshold ||
           abs(currentCenter.longitude - centerCoordinate.longitude) > threshold {
            mapView.setCenter(centerCoordinate, animated: true)
            context.coordinator.lastRecenterToken = recenterToken
        }

        // 同步标注
        syncAnnotations(on: mapView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Private

    private func syncAnnotations(on mapView: MAMapView) {
        // 移除旧的非用户位置标注
        let existingAnnotations = (mapView.annotations ?? []).compactMap { $0 as? MAPointAnnotation }
        if !existingAnnotations.isEmpty {
            mapView.removeAnnotations(existingAnnotations)
        }

        // 添加新标注
        for item in annotations {
            let annotation = MAPointAnnotation()
            annotation.coordinate = item.coordinate
            annotation.title = item.title
            annotation.subtitle = item.subtitle
            mapView.addAnnotation(annotation)
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MAMapViewDelegate {
        var lastRecenterToken = 0
        var lastScreenAnchor = CGPoint(x: 0.5, y: 0.5)

        func mapView(_ mapView: MAMapView!, viewFor annotation: MAAnnotation!) -> MAAnnotationView! {
            // 用户位置使用默认蓝点
            if annotation is MAUserLocation {
                return nil
            }

            let reuseID = "OrderPin"
            var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: reuseID) as? MAPinAnnotationView
            if annotationView == nil {
                annotationView = MAPinAnnotationView(annotation: annotation, reuseIdentifier: reuseID)
            }
            annotationView?.canShowCallout = true
            annotationView?.animatesDrop = true
            annotationView?.pinColor = .red
            return annotationView
        }
    }
}

// MARK: - Map View Wrapper

/// 根据 AMap SDK 配置状态自动选择显示地图或占位视图的包装组件。
struct MapViewWrapper: View {
    let centerCoordinate: CLLocationCoordinate2D
    var showsUserLocation: Bool = true
    var annotations: [MapAnnotationItem] = []
    var zoomLevel: CGFloat = 15.0
    var recenterToken: Int = 0
    var showsCompass: Bool = true
    var screenAnchor: CGPoint = CGPoint(x: 0.5, y: 0.5)

    var body: some View {
        #if DEBUG || DEMO
        if ProcessInfo.processInfo.environment["AIDRUN_UI_TEST_DISABLE_MAP"] == "1" {
            MapPlaceholderView()
        } else if AMapManager.isConfigured {
            AMapContainer(
                centerCoordinate: centerCoordinate,
                showsUserLocation: showsUserLocation,
                annotations: annotations,
                zoomLevel: zoomLevel,
                recenterToken: recenterToken,
                showsCompass: showsCompass,
                screenAnchor: screenAnchor
            )
            .accessibilityLabel("地图，显示当前位置和订单地点")
            .accessibilityHint("地图为辅助显示，主要操作请使用下方按钮")
        } else {
            MapPlaceholderView()
        }
        #else
        if AMapManager.isConfigured {
            AMapContainer(
                centerCoordinate: centerCoordinate,
                showsUserLocation: showsUserLocation,
                annotations: annotations,
                zoomLevel: zoomLevel,
                recenterToken: recenterToken,
                showsCompass: showsCompass,
                screenAnchor: screenAnchor
            )
            .accessibilityLabel("地图，显示当前位置和订单地点")
            .accessibilityHint("地图为辅助显示，主要操作请使用下方按钮")
        } else {
            MapPlaceholderView()
        }
        #endif
    }
}
