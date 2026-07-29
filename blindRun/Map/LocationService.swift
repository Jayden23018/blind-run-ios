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
    ///
    /// 时间戳本身不驱动 UI。Core Location 可能在坐标未变化时连续交付新时间戳；
    /// 若把每个时间戳都发布给整棵 SwiftUI 环境树，会造成无意义的全页重算。
    private(set) var lastLocationUpdatedAt: Date?

    /// CLLocationManager 的原始 WGS-84 样本；只有网络边界可将其转换为 GCJ-02。
    private(set) var latestDeviceSample: LocatedCoordinate?
    private let latestDeviceSampleSubject = CurrentValueSubject<LocatedCoordinate?, Never>(nil)

    var latestDeviceSamplePublisher: AnyPublisher<LocatedCoordinate?, Never> {
        latestDeviceSampleSubject.eraseToAnyPublisher()
    }

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

    /// 供高德地图自定义中心/标记使用；真实设备坐标在此转换，Demo 默认点已是 GCJ-02。
    var effectiveBackendLocation: CLLocationCoordinate2D {
        guard let currentLocation else { return effectiveLocation }
        return BackendCoordinateNormalizer.normalize(
            LocatedCoordinate(coordinate: currentLocation, system: .wgs84Device)
        )?.coordinate ?? currentLocation
    }

    /// 当前是否正在使用 Demo 默认坐标
    var isUsingDemoFallback: Bool {
        currentLocation == nil
    }

    /// 是否已获得定位授权
    var isAuthorized: Bool {
        #if DEBUG
        if let authorizationOverrideForTesting { return authorizationOverrideForTesting }
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
    private(set) var isEscortBackgroundModeEnabled = false
    private var isUpdatingLocation = false

    #if DEBUG
    private var authorizationOverrideForTesting: Bool?
    private var suppressHardwareUpdatesForTesting = false

    func simulateDeviceLocationForTesting(
        _ coordinate: CLLocationCoordinate2D,
        capturedAt: Date,
        authorized: Bool = true
    ) {
        suppressHardwareUpdatesForTesting = true
        authorizationOverrideForTesting = authorized
        if authorized {
            applyDeviceLocation(coordinate, capturedAt: capturedAt)
            setLocationError(nil)
        } else {
            clearDeviceLocation()
            setLocationError(.permissionDenied)
        }
    }

    func simulateLocationFailureForTesting() {
        setLocationError(.locationUnavailable)
    }
    #endif

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
        if suppressHardwareUpdatesForTesting { return }
        if isUsingUITestDemoLocation {
            setLocationError(nil)
            return
        }
        #endif
        guard isAuthorized else {
            if isDenied {
                setLocationError(.permissionDenied)
            }
            return
        }
        guard !isUpdatingLocation else { return }
        setLocationError(nil)
        isUpdatingLocation = true
        locationManager.startUpdatingLocation()
    }

    /// 停止定位更新
    func stopUpdating() {
        guard isUpdatingLocation else { return }
        isUpdatingLocation = false
        locationManager.stopUpdatingLocation()
    }

    /// 进行中服务使用适合跑步的高精度持续定位；离开后恢复普通前台策略。
    func setEscortBackgroundMode(enabled: Bool) {
        guard isEscortBackgroundModeEnabled != enabled else { return }
        isEscortBackgroundModeEnabled = enabled
        locationManager.activityType = enabled ? .fitness : .other
        locationManager.desiredAccuracy = enabled ? kCLLocationAccuracyBestForNavigation : kCLLocationAccuracyBest
        locationManager.distanceFilter = enabled ? 5 : 10
        locationManager.pausesLocationUpdatesAutomatically = !enabled
        locationManager.showsBackgroundLocationIndicator = enabled
        locationManager.allowsBackgroundLocationUpdates = enabled
        if enabled {
            startUpdating()
        }
    }

    func latestBackendSample(now: Date = Date(), freshness: TimeInterval = 15) -> LocatedCoordinate? {
        guard let sample = latestDeviceSample,
              now.timeIntervalSince(sample.capturedAt) <= freshness else { return nil }
        return BackendCoordinateNormalizer.normalize(sample)
    }

    /// 同行会话按固定 cadence 复用最近一次真实设备样本；静止不等于定位失效。
    /// 只有权限撤销或 Core Location 明确报告失败时才暂停发送。
    func latestEscortBackendSample() -> LocatedCoordinate? {
        guard isAuthorized,
              locationError == nil,
              let sample = latestDeviceSample else { return nil }
        return BackendCoordinateNormalizer.normalize(sample)
    }

    /// 请求一次定位（获取当前位置后自动停止）
    func requestOneTimeLocation() {
        #if DEBUG
        if isUsingUITestDemoLocation {
            setLocationError(nil)
            return
        }
        #endif
        guard isAuthorized else {
            if isDenied {
                setLocationError(.permissionDenied)
            }
            return
        }
        setLocationError(nil)
        locationManager.requestLocation()
    }

    private func applyDeviceLocation(
        _ coordinate: CLLocationCoordinate2D,
        capturedAt: Date
    ) {
        let sample = LocatedCoordinate(
            coordinate: coordinate,
            system: .wgs84Device,
            capturedAt: capturedAt
        )
        latestDeviceSample = sample
        lastLocationUpdatedAt = capturedAt
        latestDeviceSampleSubject.send(sample)

        guard !Self.coordinatesNearlyEqual(currentLocation, coordinate) else { return }
        currentLocation = coordinate
    }

    private func clearDeviceLocation() {
        latestDeviceSample = nil
        lastLocationUpdatedAt = nil
        latestDeviceSampleSubject.send(nil)
        if currentLocation != nil {
            currentLocation = nil
        }
    }

    private func setLocationError(_ error: LocationError?) {
        guard locationError != error else { return }
        locationError = error
    }

    private static func coordinatesNearlyEqual(
        _ lhs: CLLocationCoordinate2D?,
        _ rhs: CLLocationCoordinate2D
    ) -> Bool {
        guard let lhs else { return false }
        return abs(lhs.latitude - rhs.latitude) <= 0.000001 &&
            abs(lhs.longitude - rhs.longitude) <= 0.000001
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.applyDeviceLocation(location.coordinate, capturedAt: location.timestamp)
            self.setLocationError(nil)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            #if DEBUG
            print("[LocationService] 定位失败: \(error.localizedDescription)")
            #endif
            self.setLocationError(.locationUnavailable)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            if self.authorizationStatus != manager.authorizationStatus {
                self.authorizationStatus = manager.authorizationStatus
            }

            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                self.setLocationError(nil)
                self.startUpdating()
            case .denied, .restricted:
                self.setLocationError(.permissionDenied)
                self.clearDeviceLocation()
                self.setEscortBackgroundMode(enabled: false)
                self.stopUpdating()
            case .notDetermined:
                break
            @unknown default:
                break
            }
        }
    }
}
