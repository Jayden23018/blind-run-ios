import CoreLocation
import Foundation

// MARK: - Map Module
//
// 地图与定位模块，提供以下核心功能：
//
// 1. AMapManager       - 高德地图 SDK 初始化与 Key 管理
// 2. LocationService   - 设备定位服务（CLLocationManager 封装）
// 3. AMapContainer     - 高德地图 UIViewRepresentable 桥接
// 4. MapViewWrapper    - 自动选择地图/占位视图的包装组件
// 5. MapViewModel      - 地图显示状态管理
// 6. DistanceCalculator - 距离计算与排序工具
// 7. LocationPermissionGuard - 定位权限引导视图
// 8. MapPlaceholderView - AMap Key 缺失时的占位视图
// 9. DemoLocationBanner - Demo 默认位置提示横幅
//
// 使用方式：
// - LocationService 作为 @EnvironmentObject 注入整个 View 层级
// - AMapManager.configure() 在 App 启动时调用
// - MapViewWrapper 自动处理 SDK 未配置的降级显示
//
// 定位权限策略：
// - 不在启动时请求权限，而是在用户触发定位功能时按需请求
// - 盲人端拒绝权限：阻止创建预约
// - 志愿者端拒绝权限：阻止按距离排序和接单
//
// Demo Fallback：
// - 模拟器或定位失败时使用默认北京坐标 (39.9042, 116.4074)
// - 由 AppConstants.Defaults.demoLatitude/demoLongitude 配置

// MARK: - CLLocationCoordinate2D Extension

extension CLLocationCoordinate2D: @retroactive Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}

// MARK: - LocationPoint Convenience

extension LocationPoint {
    /// 从 LocationPoint 创建 CLLocationCoordinate2D
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// 使用设备定位创建 LocationPoint
    static func fromDevice(coordinate: CLLocationCoordinate2D, addressText: String? = nil) -> LocationPoint {
        LocationPoint(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            addressText: addressText,
            source: .deviceLocation
        )
    }

    /// 使用 Demo 默认坐标创建 LocationPoint
    static func demoDefault(addressText: String? = nil) -> LocationPoint {
        LocationPoint(
            latitude: AppConstants.Defaults.demoLatitude,
            longitude: AppConstants.Defaults.demoLongitude,
            addressText: addressText ?? "北京市（演示位置）",
            source: .demoDefault
        )
    }
}
