import Combine
import CoreLocation
import Foundation

// MARK: - Location Error

enum LocationError: String, Sendable {
    case permissionDenied
    case locationUnavailable
    case timeout
}

// MARK: - Location Service

/// 设备定位服务封装，管理 CLLocationManager 生命周期、权限状态和当前位置。
/// 作为 @EnvironmentObject 注入 View 层级，供 Map 和 Order 模块使用。
@MainActor
final class LocationService: NSObject, ObservableObject {

    // MARK: - Published State

    /// 设备当前位置坐标（授权且定位成功时有值）
    @Published var currentLocation: CLLocationCoordinate2D?

    /// 定位权限状态
    @Published var authorizationStatus: CLAuthorizationStatus

    /// 定位错误（权限拒绝或定位失败时有值）
    @Published var locationError: LocationError?

    // MARK: - Computed Properties

    /// 有效位置：优先使用真实位置，无真实位置时使用 Demo 默认坐标
    var effectiveLocation: CLLocationCoordinate2D {
        if let location = currentLocation {
            return location
        }
        return CLLocationCoordinate2D(
            latitude: AppConstants.Defaults.demoLatitude,
            longitude: AppConstants.Defaults.demoLongitude
        )
    }

    /// 当前是否正在使用 Demo 默认坐标
    var isUsingDemoFallback: Bool {
        currentLocation == nil
    }

    /// 是否已获得定位授权
    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    /// 是否被拒绝定位权限
    var isDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    /// 是否尚未请求过定位权限
    var isNotDetermined: Bool {
        authorizationStatus == .notDetermined
    }

    // MARK: - Private

    private let locationManager: CLLocationManager

    // MARK: - Init

    override init() {
        let manager = CLLocationManager()
        self.locationManager = manager
        self.authorizationStatus = manager.authorizationStatus
        super.init()

        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10 // 每移动 10 米更新一次
    }

    // MARK: - Public Methods

    /// 请求定位权限（仅在用户尚未决定时有效）
    func requestPermission() {
        guard isNotDetermined else { return }
        locationManager.requestWhenInUseAuthorization()
    }

    /// 开始持续定位更新
    func startUpdating() {
        guard isAuthorized else {
            if isDenied {
                locationError = .permissionDenied
            }
            return
        }
        locationError = nil
        locationManager.startUpdatingLocation()
    }

    /// 停止定位更新
    func stopUpdating() {
        locationManager.stopUpdatingLocation()
    }

    /// 请求一次定位（获取当前位置后自动停止）
    func requestOneTimeLocation() {
        guard isAuthorized else {
            if isDenied {
                locationError = .permissionDenied
            }
            return
        }
        locationError = nil
        locationManager.requestLocation()
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.currentLocation = location.coordinate
            self.locationError = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            #if DEBUG
            print("[LocationService] 定位失败: \(error.localizedDescription)")
            #endif
            if self.currentLocation == nil {
                self.locationError = .locationUnavailable
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus

            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                self.locationError = nil
                self.startUpdating()
            case .denied, .restricted:
                self.locationError = .permissionDenied
                self.stopUpdating()
            case .notDetermined:
                break
            @unknown default:
                break
            }
        }
    }
}
