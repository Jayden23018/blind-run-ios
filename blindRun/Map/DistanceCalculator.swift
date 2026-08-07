import CoreLocation
import Foundation

// MARK: - Distance Calculator

/// 距离计算工具，提供两点距离计算与格式化显示。
/// 使用 CoreLocation 内置的 WGS84 椭球体距离算法。
///
/// 曾经有一个 `sortOrdersByDistance`，服务于「可接订单」列表的客户端排序。
/// 那条链路已随公开订单池一起删除（系统派单上线后它就没有入口了），
/// 而后端的 `/api/orders/available` 本来就按距离升序返回并自带 `distanceKm` ——
/// 客户端重算一遍距离从来不是必要的。
enum DistanceCalculator {

    /// 计算两个坐标点之间的距离（米）
    static func distance(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) -> CLLocationDistance {
        let originLocation = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        let destinationLocation = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        return originLocation.distance(from: destinationLocation)
    }

    static func distanceFromDeviceToBackend(
        deviceCoordinate: CLLocationCoordinate2D,
        backendCoordinate: CLLocationCoordinate2D
    ) -> CLLocationDistance {
        let normalized = BackendCoordinateNormalizer.normalize(
            LocatedCoordinate(coordinate: deviceCoordinate, system: .wgs84Device)
        )?.coordinate ?? deviceCoordinate
        return distance(from: normalized, to: backendCoordinate)
    }

    /// 格式化距离为人类可读字符串
    /// - < 1000m: "XXX 米"（取整到十位）
    /// - >= 1000m: "X.X 公里"（保留一位小数）
    static func formattedDistance(_ meters: CLLocationDistance) -> String {
        if meters < 1000 {
            let rounded = Int((meters / 10).rounded()) * 10
            return "\(max(rounded, 10)) 米"
        } else {
            let km = meters / 1000.0
            return String(format: "%.1f 公里", km)
        }
    }
}
