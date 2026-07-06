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

    /// 最近一次真实定位更新时间，供非视觉摘要和验收记录使用。
    @Published var lastLocationUpdatedAt: Date?

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
        #if DEBUG
        if isUsingUITestDemoLocation {
            return true
        }
        #endif
        return authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    /// 是否被拒绝定位权限
    var isDenied: Bool {
        #if DEBUG
        if isUsingUITestDemoLocation {
            return false
        }
        #endif
        return authorizationStatus == .denied || authorizationStatus == .restricted
    }

    /// 是否尚未请求过定位权限
    var isNotDetermined: Bool {
        #if DEBUG
        if isUsingUITestDemoLocation {
            return false
        }
        #endif
        return authorizationStatus == .notDetermined
    }

    var readableCurrentLocationSummary: String {
        #if DEBUG
        if isUsingUITestDemoLocation {
            return "当前位置：演示定位已启用，适合模拟器测试。"
        }
        #endif
        if isDenied {
            return "需要开启定位权限后才能获取当前位置。"
        }
        if currentLocation != nil {
            let updateText = lastLocationUpdatedAt.map {
                "，更新时间 \($0.formatted(date: .omitted, time: .shortened))"
            } ?? ""
            return "当前位置：已获取设备定位\(updateText)。"
        }
        if isAuthorized {
            return "当前位置：正在获取设备定位。"
        }
        if isNotDetermined {
            return "当前位置：等待定位权限授权。"
        }
        if isUsingDemoFallback {
            return "当前位置：演示定位已启用，适合模拟器测试。"
        }
        return "当前位置：正在获取设备定位。"
    }

    // MARK: - Private

    private let locationManager: CLLocationManager

    #if DEBUG
    private var isUsingUITestDemoLocation: Bool {
        ProcessInfo.processInfo.environment["AIDRUN_UI_TEST_FORCE_DEMO_LOCATION"] == "1"
    }
    #endif

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
        #if DEBUG
        guard !isUsingUITestDemoLocation else { return }
        #endif
        guard isNotDetermined else { return }
        locationManager.requestWhenInUseAuthorization()
    }

    /// 开始持续定位更新
    func startUpdating() {
        #if DEBUG
        if isUsingUITestDemoLocation {
            locationError = nil
            return
        }
        #endif
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
        #if DEBUG
        if isUsingUITestDemoLocation {
            locationError = nil
            return
        }
        #endif
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
            self.lastLocationUpdatedAt = Date()
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
