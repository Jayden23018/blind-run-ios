import CoreLocation
import Foundation

// MARK: - Distance Calculator

/// 距离计算工具，提供两点距离计算、格式化显示和按距离排序功能。
/// 使用 CoreLocation 内置的 WGS84 椭球体距离算法。
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

    /// 按距离对订单列表排序（从近到远）
    static func sortOrdersByDistance(
        orders: [OrderDetailResponse],
        from location: CLLocationCoordinate2D
    ) -> [(order: OrderDetailResponse, distance: CLLocationDistance)] {
        let ordersWithDistance = orders.compactMap { order -> (order: OrderDetailResponse, distance: CLLocationDistance)? in
            guard let lat = order.startLatitude, let lng = order.startLongitude else {
                return nil
            }
            let orderCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            let dist = distance(from: location, to: orderCoordinate)
            return (order: order, distance: dist)
        }
        return ordersWithDistance.sorted { $0.distance < $1.distance }
    }
}
