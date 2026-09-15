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

    /// 紧急场景下的距离**分档**，不给精确值。
    ///
    /// 🔴 **为什么不复用 `formattedDistance`。** 那个给的是「80 米」这种精确读数，
    /// 用在接驳（志愿者按地图找人）上是对的。但求助那一屏上的距离是两台手机
    /// **各自的 GPS 读数之差** —— 城市里单台误差就可达十几米，两台叠起来更大。
    /// 印一个「距你约 8 米」会让志愿者以为对方就在手边、抬头没看见就开始怀疑数据，
    /// 而真正该做的是往那个方向找。分档说的是**能据以行动的那部分**，
    /// 精确到米说的是一个 App 其实并不知道的事。
    ///
    /// 档位取值对应三种完全不同的动作：抬头找人 / 往那边走 / 边走边打电话。
    static func proximityBand(_ meters: CLLocationDistance) -> String {
        switch meters {
        case ..<30: return "就在附近"
        case ..<150: return "约几十米"
        case ..<1_000: return "几百米外"
        default: return "较远"
        }
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
