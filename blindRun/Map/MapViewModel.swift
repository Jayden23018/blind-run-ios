import Combine
import CoreLocation
import SwiftUI

// MARK: - Map ViewModel

/// 地图视图模型，管理地图显示状态、标注和用户位置跟踪。
/// 通过 Combine 订阅 LocationService 的位置更新来同步地图中心。
@MainActor
final class MapViewModel: ObservableObject {

    // MARK: - Published State

    /// 地图中心坐标
    @Published var centerCoordinate: CLLocationCoordinate2D

    /// 地图标注列表
    @Published var annotations: [MapAnnotationItem] = []

    /// 地图缩放级别
    @Published var zoomLevel: CGFloat = 15.0

    /// 是否显示用户位置蓝点
    @Published var showsUserLocation = true

    // MARK: - Private

    private weak var locationService: LocationService?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init() {
        // 初始使用 Demo 默认坐标
        self.centerCoordinate = CLLocationCoordinate2D(
            latitude: AppConstants.Defaults.demoLatitude,
            longitude: AppConstants.Defaults.demoLongitude
        )
    }

    // MARK: - Configuration

    /// 配置 ViewModel，订阅 LocationService 的位置更新。
    /// 遵循项目 MVVM 模式，通过 configure 方法注入依赖。
    func configure(with locationService: LocationService) {
        self.locationService = locationService

        // 初始化为当前有效位置
        centerCoordinate = locationService.effectiveLocation

        // 订阅位置变化
        locationService.$currentLocation
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] coordinate in
                self?.centerCoordinate = coordinate
            }
            .store(in: &cancellables)
    }

    // MARK: - Public Methods

    /// 将地图中心移动到用户当前位置
    func centerOnUser() {
        guard let locationService else { return }
        centerCoordinate = locationService.effectiveLocation
    }

    /// 在地图上显示订单出发地点标注
    func showOrderLocation(_ point: LocationPoint) {
        let annotation = MapAnnotationItem(
            id: "order_start",
            coordinate: CLLocationCoordinate2D(
                latitude: point.latitude,
                longitude: point.longitude
            ),
            title: point.addressText ?? "出发地点",
            subtitle: nil
        )
        annotations = [annotation]
    }

    /// 在地图上显示多个订单位置标注（用于志愿者查看附近订单）
    func showOrderLocations(_ orders: [OrderDetailResponse]) {
        annotations = orders.compactMap { order in
            guard let lat = order.startLatitude, let lng = order.startLongitude else { return nil }
            return MapAnnotationItem(
                id: String(order.orderId),
                coordinate: CLLocationCoordinate2D(
                    latitude: lat,
                    longitude: lng
                ),
                title: order.startAddress ?? "出发地点",
                subtitle: order.blindName
            )
        }
    }

    /// 清除所有标注
    func clearAnnotations() {
        annotations = []
    }
}
