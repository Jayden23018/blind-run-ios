import CoreLocation
import MAMapKit
import UIKit

// 跑步记录（#823）在高德桥接层上加的三件事：低饱和底图、取景边距变了就重新取景、地图尺寸变了就重新取景。
// 单独成文件：`AMapContainer.swift` 已超长，SwiftLint 棘轮不许它再变长。

extension AMapContainer {
    /// 跑步记录（列表小图、详情大图）的低饱和底图（#823 第 10 条）：底图与路线之间铺一层半透明白 / 黑，让彩色路线跳出来。
    /// 覆盖中心 ±1°（约 100 km），一次跑步拖不出这个范围；压在底图文字之上（`aboveLabels`），路线比它后加，所以在它上面。
    // ponytail: 高德控制台自定义样式能做得更干净，但开了 `customMapStyleEnabled` 审图号会变空（issue #382，
    // 见 `AMapHostView.layoutSubviews` 的断言），且样式文件要负责人的控制台账号导出。拿到带审图号的方案再换。
    func applyMutedWash(on mapView: MAMapView, coordinator: Coordinator) {
        let c = centerCoordinate
        var corners = [
            CLLocationCoordinate2D(latitude: c.latitude - 1, longitude: c.longitude - 1),
            CLLocationCoordinate2D(latitude: c.latitude - 1, longitude: c.longitude + 1),
            CLLocationCoordinate2D(latitude: c.latitude + 1, longitude: c.longitude + 1),
            CLLocationCoordinate2D(latitude: c.latitude + 1, longitude: c.longitude - 1),
        ]
        guard let wash = MAPolygon(coordinates: &corners, count: UInt(corners.count)) else { return }
        coordinator.mutedWash = wash
        mapView.add(wash, level: .aboveLabels)
    }

    /// 跑步记录的地图：铺降饱和那层，并在地图摆到真实尺寸后重新取景。
    func configureRunRecordMap(_ hostView: AMapHostView, coordinator: Coordinator) {
        applyMutedWash(on: hostView.mapView, coordinator: coordinator)
        hostView.onLayout = { [weak coordinator] mapView in coordinator?.refitPrimaryIfSizeChanged(on: mapView) }
    }

    /// 主路线按当前边距取景，并记下这次用的边距和地图尺寸。
    func fitPrimary(_ overlay: MAPolyline, signature: String, on mapView: MAMapView, coordinator: Coordinator) {
        mapView.setVisibleMapRect(overlay.boundingMapRect, edgePadding: fitEdgePadding, animated: false)
        coordinator.lastFittedPrimarySignature = signature
        coordinator.lastFittedPadding = fitEdgePadding
        coordinator.lastFittedSize = mapView.bounds.size
    }

    /// 取景边距变了（页面打开后头部才量出实际高度；旋转、字号变化）而路线没变：按新边距重新取景（#823 第 11 条）。
    func refitPrimaryIfPaddingChanged(on mapView: MAMapView, coordinator: Coordinator) {
        guard coordinator.lastFittedPadding != fitEdgePadding,
              let primary = coordinator.polylinesByID.values.first(where: \.isPrimary) else { return }
        fitPrimary(primary.overlay, signature: primary.signature, on: mapView, coordinator: coordinator)
    }
}

extension AMapContainer.Coordinator {
    /// 地图尺寸变了就按上次的边距重新取景（负责人 11-07 第二轮第 4 条：列表小图只看得到一段路线）。
    /// 根因：SwiftUI 第一次 `updateUIView` 时地图还是零尺寸，那次取景按 0×0 算出的缩放级别不对；
    /// 详情大图后来因为头部量出高度、边距变了而重新取景，碰巧好了，列表小图边距固定，一直停在错的那次。
    func refitPrimaryIfSizeChanged(on mapView: MAMapView) {
        let size = mapView.bounds.size
        guard size.width > 0, size.height > 0, size != lastFittedSize,
              let padding = lastFittedPadding,
              let primary = polylinesByID.values.first(where: \.isPrimary) else { return }
        mapView.setVisibleMapRect(primary.overlay.boundingMapRect, edgePadding: padding, animated: false)
        lastFittedSize = size
    }

    /// 明暗或「增强对比度」变了：删掉跑后路线三层（由 `syncPolylines` 按新配色加回），降饱和那层删掉重加（渲染器按新明暗重取）。
    /// 路线刚被删，加回时仍在降饱和那层上面。
    func resetRunRecordStyling(on mapView: MAMapView) {
        for (id, entry) in polylinesByID where entry.routeStyle != nil {
            remove(entry, from: mapView)
            polylinesByID.removeValue(forKey: id)
        }
        if let wash = mutedWash {
            mapView.remove(wash)
            mapView.add(wash, level: .aboveLabels)
        }
    }

    /// 降饱和那层：浅色白 40% / 深色黑 45%（#823 PLAN「退路」原值）。不是这层返回 nil。
    // ponytail: 真机前的起始值 —— 底图还抢眼就往上调，路名看不清就往下调。
    func mutedWashRenderer(for overlay: MAOverlay) -> MAOverlayRenderer? {
        guard let wash = overlay as? MAPolygon, wash === mutedWash else { return nil }
        let renderer = MAPolygonRenderer(polygon: wash)
        renderer?.fillColor = isDark ? UIColor.black.withAlphaComponent(0.45) : UIColor.white.withAlphaComponent(0.4)
        renderer?.strokeColor = .clear
        renderer?.lineWidth = 0
        return renderer
    }
}
