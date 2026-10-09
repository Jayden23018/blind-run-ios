import Combine
import CoreLocation
import Foundation

// MARK: - Location Error

enum LocationError: String, Sendable {
    case permissionDenied
    case locationUnavailable
    case timeout
    /// 已授权，但系统「精确位置」关闭：只拿得到区域代表点（约 5 公里）。
    ///
    /// **`LocationService.locationError` 从不取这个值** —— 那个属性还是陪跑会话的闸门，
    /// 模糊位置下同行位置照常共享（陪跑员端按 `accuracyM` 放宽方位扇形）。
    /// 它只由 `EmergencyCoordinator.locationFailureReason(using:)` 产出，供求助文案分岔。
    case preciseLocationOff
}

// MARK: - Accuracy Policy

/// 定位精度的阈值。与陪跑员端 `VolunteerRunTip.weakAccuracyMeters` 取同一个数，
/// 用例 `PreciseLocationGateTests.testWeakAccuracyThresholdMatchesTheVolunteerSide` 钉住两者相等。
enum LocationAccuracyPolicy {
    static let weakAccuracyMeters: Double = 50

    /// 精度差于阈值时返回米数，否则 nil。精度未知（Core Location 给负数，`LocatedCoordinate` 已转成 nil）
    /// 不算差 —— 没有依据就不说「不准」。
    static func metersIfWeak(_ sample: LocatedCoordinate?) -> Double? {
        guard let meters = sample?.horizontalAccuracy, meters > weakAccuracyMeters else { return nil }
        return meters
    }
}

/// 临时精确位置的用途键。值必须与 `Info.plist` 的 `NSLocationTemporaryUsageDescriptionDictionary` 键一致，
/// 否则系统不弹（SDK `CLLocationManager.h` 原文：「Passing any other string would result in the prompt not being displayed」）。
enum PreciseLocationPurpose: String, Sendable {
    case bookingStartPoint = "AidRunBookingStartPoint"
    case escortRun = "AidRunEscortRun"
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

    /// 系统「精确位置」开关。关掉后系统把位置吸附到区域代表点，精度约 5 公里，样本最旧可能 20 分钟
    /// （iOS 26.2 SDK `CLLocationManager.h` 对 `CLAccuracyAuthorizationReducedAccuracy` 的注释）。
    @Published private(set) var accuracyAuthorization: CLAccuracyAuthorization

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

    /// UI 测试是否强制启用了演示定位。正式构建恒为 `false`。
    ///
    /// 存在的理由只有一个：下单侧要能把「演示坐标」和「真实定位」分开对待，
    /// 而做这个判断的地方（`BlindBookingViewModel`）不该知道 UI 测试的环境变量名。
    var isDemoLocationForcedForTesting: Bool {
        #if DEBUG
        return isUsingUITestDemoLocation
        #else
        return false
        #endif
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
        if let authorizationOverrideForTesting { return !authorizationOverrideForTesting }
        if isUsingUITestDemoLocation {
            return false
        }
        #endif
        return authorizationStatus == .denied || authorizationStatus == .restricted
    }

    /// 是否尚未请求过定位权限
    var isNotDetermined: Bool {
        #if DEBUG
        if authorizationOverrideForTesting != nil { return false }
        if isUsingUITestDemoLocation {
            return false
        }
        #endif
        return authorizationStatus == .notDetermined
    }

    /// 已授权、但「精确位置」关闭。此时拿到的坐标是区域代表点，不能当作求助坐标或出发地点。
    ///
    /// 只在已授权时成立：未授权时 SDK 说 `accuracyAuthorization` 无意义（`.notDetermined` 下也可能报 full）。
    var isPreciseLocationOff: Bool {
        #if DEBUG
        if let preciseLocationOffOverrideForTesting { return preciseLocationOffOverrideForTesting }
        // UI 测试拿不到「系统设置里关掉精确位置」这一步，用启动开关模拟（`AccessibilityAuditTests`）。
        if ProcessInfo.processInfo.environment["AIDRUN_UI_TEST_PRECISE_LOCATION_OFF"] == "1" { return true }
        if isUsingUITestDemoLocation { return false }
        #endif
        return isAuthorized && accuracyAuthorization == .reducedAccuracy
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
    private var preciseLocationOffOverrideForTesting: Bool?
    /// 申请过的临时精确位置用途，按调用顺序。接缝打开时不碰 `CLLocationManager`。
    private(set) var temporaryPreciseLocationRequestsForTesting: [PreciseLocationPurpose] = []

    /// 把「精确位置」开关钉在给定状态。与 `simulateDeviceLocationForTesting` 同一种接缝：
    /// 打开后申请临时精确位置只记账，不弹系统窗。
    func simulatePreciseLocationOffForTesting(_ off: Bool = true) {
        preciseLocationOffOverrideForTesting = off
        objectWillChange.send()
    }

    func simulateDeviceLocationForTesting(
        _ coordinate: CLLocationCoordinate2D,
        capturedAt: Date,
        authorized: Bool = true,
        horizontalAccuracy: Double? = nil,
        speed: Double? = nil
    ) {
        suppressHardwareUpdatesForTesting = true
        authorizationOverrideForTesting = authorized
        if authorized {
            applyDeviceLocation(coordinate, capturedAt: capturedAt, horizontalAccuracy: horizontalAccuracy, speed: speed)
            setLocationError(nil)
        } else {
            clearDeviceLocation()
            setLocationError(.permissionDenied)
        }
    }

    /// 把服务钉在「已授权、但一个真实定位都还没拿到」的状态，并从此忽略硬件回调。
    ///
    /// 真机上 CoreLocation 几毫秒内就会送来真实坐标，所以裸 `LocationService()` 构造出的
    /// 「无定位」状态活不过一次 runloop —— 拿它断言演示坐标兜底行为是在赌回调时序，不是在测守卫。
    /// 与 `RecordingCue.observerForTesting`、`MockAPIClient.voiceClockForTesting` 是同一种接缝。
    func simulateMissingDeviceLocationForTesting() {
        suppressHardwareUpdatesForTesting = true
        authorizationOverrideForTesting = true
        clearDeviceLocation()
        setLocationError(nil)
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
        self.accuracyAuthorization = manager.accuracyAuthorization
        super.init()

        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10 // 每移动 10 米更新一次
        // **在唯一的构造点无条件关掉自动暂停，不交给任何分支去设。**
        //
        // Core Location 的默认值是 `true`，而 Apple 的原文是（2026-08-20 核实，
        // `docs/research/ios-location-pause-and-ats-20260820.md` §1）：
        // 「For apps that have in-use authorization, a pause to location updates ends access to
        //  location changes **until the app launches again**」。
        // 本 App 只申请 in-use（全仓无 `requestAlwaysAuthorization`），所以一次暂停 = 到重启为止
        // 都拿不到新位置，而调用方完全不知道。
        //
        // 此前这一行写在 `setEscortBackgroundMode` 里，形如 `= !enabled`，于是：
        // ① 该方法开头的 `guard isEscortBackgroundModeEnabled != enabled` 在初值 `false` 时
        //    把第一次 `enabled: false` 的调用整段吞掉，这一行从未执行；
        // ② 即便执行，非 `IN_PROGRESS`（`DRIVER_EN_ROUTE` / `DRIVER_ARRIVED`）反而会把它设回 `true`。
        // 而志愿者在路上等红灯、或到了集合点站着等人，正是「位置不变」的典型场景 ——
        // iOS 判定可以暂停，盲人正在原地等一个据说「已到达」的人。
        manager.pausesLocationUpdatesAutomatically = false
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

    /// 精确位置关闭时，申请临时精确位置；开着时什么都不做。
    ///
    /// 系统可能不弹（App 在后台、或系统自行决定），所以调用方的文案只能写「如果弹出提示」。
    /// 用户的回答经 `locationManagerDidChangeAuthorization` 回来，这里不需要 completion。
    /// 授予后在前台、或开着后台定位指示器的陪跑会话期间都不过期（SDK 注释）。
    func requestTemporaryPreciseLocation(for purpose: PreciseLocationPurpose) {
        guard isPreciseLocationOff else { return }
        #if DEBUG
        if preciseLocationOffOverrideForTesting != nil || suppressHardwareUpdatesForTesting {
            temporaryPreciseLocationRequestsForTesting.append(purpose)
            return
        }
        #endif
        locationManager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: purpose.rawValue)
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
        // `pausesLocationUpdatesAutomatically` **不在这里设** —— 见 `init`。它是全 App 恒 false 的
        // 不变量，放在这个带 guard 的分支方法里正是它此前从未生效的原因。
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

    /// 同行会话可以接受的最大样本年龄。
    ///
    /// **不是 15 秒**（求助路径 `latestBackendSample` 那道闸的值）。上报周期是 5 秒，而
    /// `distanceFilter` 是 5–10 米 —— 正常走动时样本随时在来，60 秒是个很宽的门；
    /// 取这么宽正是为了不把「人站住了、坐标没变」误判成定位失效。
    ///
    /// ⚠️ 已知代价：非陪跑模式下 `distanceFilter = 10`，本仓库自己记着「站着不动 Core Location
    /// 就不推新样本」（`BlindBookingView.swift:967-977`，那条注释来自一次真实的线上误判）。
    /// 所以 `DRIVER_EN_ROUTE` / `DRIVER_ARRIVED` 期间原地站够 60 秒仍可能报一次
    /// 「设备位置暂时不可用」。相对于「让对端一直以为陈旧坐标是新的」，这一侧的代价更小 ——
    /// 说错「位置暂时不可用」用户还能自己判断，说对了「15 秒内的新位置」而其实是十分钟前的，
    /// 看不见屏幕的人无从分辨。
    nonisolated static let escortSampleMaxAge: TimeInterval = 60

    /// 同行会话按固定 cadence 复用最近一次真实设备样本；**坐标静止不等于定位失效，
    /// 但样本停更等于**。
    ///
    /// 这两件事此前被当成一件事：原实现只看权限与 `locationError`，不看样本年龄，
    /// 注释还写明是故意的。后果是 GPS 卡住（隧道、地库、商场、iOS 自动暂停）时
    /// Core Location 常常**不报错**、只是不再送新样本，于是发送端每 5 秒把同一个陈旧坐标
    /// 重发一次，服务端每次打上**当前**时间戳，接收端每次都判定「这是 15 秒内的新位置」。
    /// 上行报文里没有采样时间（`WSLocationUpdateMessage` 只有 `type/lat/lng`），
    /// 对端因此没有任何办法自己看穿 —— 只能由发送端不发。
    ///
    /// 返回 nil 同时达成两件事，不需要各自再加判断：
    /// `sendLatestLocation` 的 `guard let sample` 停发（连 `escort-location-send` 的诊断事件
    /// 都不会产生），`refreshHealth` 的 `guard ... != nil` 落到 `.waitingForLocation`。
    ///
    /// 根因修法是后端给 `WSLocationUpdateMessage` 补 `capturedAt` 并透传给对端 —— 已列入待投递。
    func latestEscortBackendSample(
        now: Date = Date(),
        maxAge: TimeInterval = LocationService.escortSampleMaxAge
    ) -> LocatedCoordinate? {
        guard isAuthorized,
              locationError == nil,
              let sample = latestDeviceSample,
              now.timeIntervalSince(sample.capturedAt) <= maxAge else { return nil }
        return BackendCoordinateNormalizer.normalize(sample)
    }

    /// Core Location 自行暂停之后的恢复。
    ///
    /// `init` 里已经把 `pausesLocationUpdatesAutomatically` 关掉，所以正常情况下这条路走不到。
    /// 仍然实现它，是因为 Apple 明说暂停之后**重启是 App 自己的责任**，而这个 App 里
    /// 「不再有新位置」这件事必须被说出来，不能安静地停在最后一个坐标上 ——
    /// 那正是 F2 描述的那条链路（每 5 秒把同一个陈旧坐标重发一次，对端每次都判成新位置）。
    ///
    /// 两行顺序不能反，各自都有理由：
    /// - 先把 `isUpdatingLocation` 归位，否则 `startUpdating()` 的幂等 guard 会把这次重启整个吞掉
    ///   （暂停时它仍是 `true`，Core Location 停了但这边不知道）。
    /// - `setLocationError` 放在 `startUpdating()` **之后**，因为后者会先把错误清成 `nil`。
    ///   这一格由下一次真实回调（`didUpdateLocations`）清掉；在那之前
    ///   `latestEscortBackendSample()` 返回 nil，同行会话停发并落到 `.waitingForLocation`。
    func handlePausedLocationUpdates() {
        isUpdatingLocation = false
        startUpdating()
        setLocationError(.locationUnavailable)
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
        capturedAt: Date,
        horizontalAccuracy: Double? = nil,
        speed: Double? = nil
    ) {
        let sample = LocatedCoordinate(
            coordinate: coordinate,
            system: .wgs84Device,
            capturedAt: capturedAt,
            horizontalAccuracy: horizontalAccuracy,
            speed: speed
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
            #if DEBUG
            if self.suppressHardwareUpdatesForTesting { return }
            #endif
            self.applyDeviceLocation(
                location.coordinate,
                capturedAt: location.timestamp,
                horizontalAccuracy: location.horizontalAccuracy,
                speed: location.speed
            )
            self.setLocationError(nil)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            #if DEBUG
            if self.suppressHardwareUpdatesForTesting { return }
            print("[LocationService] 定位失败: \(error.localizedDescription)")
            #endif
            self.setLocationError(.locationUnavailable)
        }
    }

    nonisolated func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        Task { @MainActor in
            #if DEBUG
            if self.suppressHardwareUpdatesForTesting { return }
            #endif
            self.handlePausedLocationUpdates()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            #if DEBUG
            if self.suppressHardwareUpdatesForTesting { return }
            #endif
            if self.authorizationStatus != manager.authorizationStatus {
                self.authorizationStatus = manager.authorizationStatus
            }
            // 「精确位置」开关的变化也走这个回调（SDK `CLLocationManagerDelegate.h` 原文：
            // 「Invoked when either the authorizationStatus or accuracyAuthorization properties change」）。
            if self.accuracyAuthorization != manager.accuracyAuthorization {
                self.accuracyAuthorization = manager.accuracyAuthorization
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
