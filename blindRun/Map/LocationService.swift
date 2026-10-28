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
    /// **`LocationService.locationError` 从不取这个值** —— 同行会话自己读 `isPreciseLocationOff`
    /// 停发同行位置、亮健康横幅（#407），不经过 `locationError`。
    /// 它只由 `EmergencyCoordinator.locationFailureReason(using:)` 产出，供求助文案分岔。
    case preciseLocationOff
    /// 当前角色在本机没有位置轨迹同意（#368，按角色判，见 `AppState.isEmergencyLocationSharingBlocked`）。
    /// 与 `preciseLocationOff` 一样只供求助文案分岔，由 `EmergencyCoordinator.locationFailureReason(using:sharingBlocked:)` 产出。
    case locationSharingNotConsented
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
    /// 盲人端陪跑（说明讲求助与陪跑员找人）。
    case escortRun = "AidRunEscortRun"
    /// 陪跑员端陪跑（#407）。不借用上一条：那条讲的是「求助才能带上你的准确位置」，对陪跑员不成立。
    case escortVolunteer = "AidRunEscortVolunteer"
}

/// 同行会话的定位档位（#523）。
enum EscortLocationMode: Equatable, Sendable {
    /// 没有同行会话：普通前台策略，不在后台定位。
    case off
    /// 出发 / 汇合：后台继续共享位置，普通精度。
    case sharing
    /// 跑步中：后台 + 跑步专用的增强精度。
    case running
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

    /// 「精确位置」从关到开时丢掉手里的样本：那是关着时拿到的区域代表点，而它还在 15 秒新鲜度内，
    /// 开关一开 `isPreciseLocationOff` 就放行它 —— 刚允许临时精确位置就按求助，会带着几公里外的点发出。
    /// 清掉后取坐标的一方照常等下一个真实样本（CoreLocation 几毫秒内就会送来）。
    func applyAccuracyAuthorization(_ newValue: CLAccuracyAuthorization) {
        guard accuracyAuthorization != newValue else { return }
        let leavesReducedAccuracy = accuracyAuthorization == .reducedAccuracy
        accuracyAuthorization = newValue
        if leavesReducedAccuracy { clearDeviceLocation() }
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
    /// 同行会话的定位档位（#523）。`.off` = 没有同行会话。
    private(set) var escortLocationMode: EscortLocationMode = .off
    /// 允许后台继续定位（出发 / 汇合 / 跑步三态都允许）。
    var isEscortBackgroundModeEnabled: Bool { escortLocationMode != .off }
    private(set) var isUpdatingLocation = false
    /// 要过持续定位、还没撤回的调用方（#413 / #425）。授权回调只替这些调用方开定位，集合空了才停硬件。
    ///
    /// 和 `isUpdatingLocation` 分开存：没授权时 `startUpdating(for:)` 被挡住、硬件没开，但意图要留着，
    /// 授权弹窗答「允许」之后才能补上；权限被收回时硬件停了，意图也留着，重新打开权限就恢复。
    private(set) var updateReasons: Set<LocationUpdateReason> = []

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

    /// 授权回调的接缝：从此忽略 `CLLocationManager` 的真实回调，开 / 停持续定位只记账不碰硬件。
    /// 授权变化改由用例直接调 `handleAuthorizationChange` 喂进来 —— 测试机上真实的授权状态不固定。
    private var interceptsLocationManagerForTesting = false
    private(set) var hardwareUpdateStartsForTesting = 0

    func interceptLocationManagerForTesting() {
        interceptsLocationManagerForTesting = true
    }
    #endif

    #if DEBUG
    private var isUsingUITestDemoLocation: Bool {
        ProcessInfo.processInfo.environment["AIDRUN_UI_TEST_FORCE_DEMO_LOCATION"] == "1"
    }

    /// 「系统定位授权框不早于位置轨迹同意」（#368）的调试期断言（#414）。由根视图装配成
    /// 「当前角色在本机有没有位置轨迹同意」；`requestPermission()` 在它答 false 时直接崩。
    ///
    /// 断言排在演示定位的早退**之前**：UI 用例都强制演示定位，`requestPermission()` 在那种构建里
    /// 什么都不做，于是重新加回一行无闸的调用不会让任何用例变红。专测同意页的用例
    /// （`AIDRUN_UI_TEST_FORCE_LOCATION_TRACK_CONSENT=1`）会走到这里，App 崩掉 = 用例红。
    /// 其余 UI 用例跳过同意，这里恒为 true，不受影响。只在 DEBUG 里装，不改发布包的行为。
    var trackConsentPreconditionForDebug: (() -> Bool)?
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
        // 此前这一行写在旧的 `setEscortBackgroundMode` 里，形如 `= !enabled`，于是：
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
        if let precondition = trackConsentPreconditionForDebug, !precondition() {
            assertionFailure("系统定位授权框早于位置轨迹同意：这一处 requestPermission() 前要先判 hasLocationTrackConsent（#368）")
        }
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

    /// 替 `reason` 开始持续定位。没授权时只记下意图，等授权回调补上。
    func startUpdating(for reason: LocationUpdateReason) {
        #if DEBUG
        if suppressHardwareUpdatesForTesting { return }
        if isUsingUITestDemoLocation {
            setLocationError(nil)
            return
        }
        #endif
        updateReasons.insert(reason)
        resumeHardwareUpdates()
    }

    private func resumeHardwareUpdates() {
        guard isAuthorized else {
            if isDenied {
                setLocationError(.permissionDenied)
            }
            return
        }
        guard !isUpdatingLocation else { return }
        setLocationError(nil)
        isUpdatingLocation = true
        #if DEBUG
        if interceptsLocationManagerForTesting {
            hardwareUpdateStartsForTesting += 1
            return
        }
        #endif
        locationManager.startUpdatingLocation()
    }

    /// 撤回 `reason` 这一份意图。别的调用方还要时硬件照开；最后一份撤回才停，之后的授权回调也不再自动开。
    func stopUpdating(for reason: LocationUpdateReason) {
        updateReasons.remove(reason)
        guard updateReasons.isEmpty else { return }
        haltHardwareUpdates()
    }

    /// 所有调用方的意图一起撤回并停硬件。只给账号边界用（退出登录、换到没同意过的账号或角色，#417）：
    /// 上一个人留下的任何一份意图都不能被下一次授权回调开回来。
    func stopAllUpdates() {
        updateReasons.removeAll()
        haltHardwareUpdates()
    }

    private func haltHardwareUpdates() {
        guard isUpdatingLocation else { return }
        isUpdatingLocation = false
        #if DEBUG
        if interceptsLocationManagerForTesting { return }
        #endif
        locationManager.stopUpdatingLocation()
    }

    /// 同行会话三态都允许后台继续定位（#523）：陪跑员按「出发」后通常切到外部导航，本 App 进后台，
    /// 此前只在 `IN_PROGRESS` 允许后台，盲人那边看到的陪跑员位置就停在出发点。两端的位置轨迹同意
    /// 都写了「从出发到跑步结束……锁屏后仍在定位」，系统的蓝色定位标记同时告知。
    /// 跑步专用的增强精度（fitness、导航级精度、5 米）仍只在 `IN_PROGRESS`（`.running`）。
    func setEscortLocationMode(_ mode: EscortLocationMode) {
        guard escortLocationMode != mode else { return }
        escortLocationMode = mode
        let running = mode == .running
        locationManager.activityType = running ? .fitness : .other
        locationManager.desiredAccuracy = running ? kCLLocationAccuracyBestForNavigation : kCLLocationAccuracyBest
        locationManager.distanceFilter = running ? 5 : 10
        // `pausesLocationUpdatesAutomatically` **不在这里设** —— 见 `init`。它是全 App 恒 false 的
        // 不变量，放在这个带 guard 的分支方法里正是它此前从未生效的原因。
        let background = mode != .off
        locationManager.showsBackgroundLocationIndicator = background
        locationManager.allowsBackgroundLocationUpdates = background
        // 这里不开定位：开不开由调用方的意图决定（同行会话先 `startUpdating(for: .escortSession)` 再调这里）。
        // 这个方法只改精度与后台策略，否则它会替一个不知道是谁的调用方立起意图、没人撤回（#425）。
    }

    /// Core Location 自行暂停之后的恢复。
    ///
    /// `init` 里已经把 `pausesLocationUpdatesAutomatically` 关掉，所以正常情况下这条路走不到。
    /// 仍然实现它，是因为 Apple 明说暂停之后**重启是 App 自己的责任**，而这个 App 里
    /// 「不再有新位置」这件事必须被说出来，不能安静地停在最后一个坐标上 ——
    /// 那正是 F2 描述的那条链路（每 5 秒把同一个陈旧坐标重发一次，对端每次都判成新位置）。
    ///
    /// 两行顺序不能反，各自都有理由：
    /// - 先把 `isUpdatingLocation` 归位，否则 `resumeHardwareUpdates()` 的幂等 guard 会把这次重启整个吞掉
    ///   （暂停时它仍是 `true`，Core Location 停了但这边不知道）。
    /// - `setLocationError` 放在 `resumeHardwareUpdates()` **之后**，因为后者会先把错误清成 `nil`。
    ///   这一格由下一次真实回调（`didUpdateLocations`）清掉；在那之前
    ///   `latestEscortBackendSample()` 返回 nil，同行会话停发并落到 `.waitingForLocation`。
    func handlePausedLocationUpdates() {
        isUpdatingLocation = false
        // 只恢复还有人要的定位（#413）：迟到的暂停回调不能把已经全部撤回的意图重新立起来。
        if !updateReasons.isEmpty {
            resumeHardwareUpdates()
        }
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
            // 只挡本服务自己那台 manager 的真实回调；用例传进来的替身照常转发，接线本身才有人守。
            if self.interceptsLocationManagerForTesting, manager === self.locationManager { return }
            #endif
            self.handleAuthorizationChange(manager.authorizationStatus, accuracy: manager.accuracyAuthorization)
        }
    }
}

extension LocationService {

    /// 🔴 **「已授权」不等于「开定位」（#413）。** `CLLocationManager` 一创建就回调一次，
    /// 这里若无条件开定位，已授权的设备一启动 App 就在本机持续定位 —— 早于位置轨迹同意（#368），
    /// 也不看角色和订单。所以只替 `startUpdating(for:)` 要过、还没撤回的调用方开：
    /// 预约页、接单开关、同意页都是先 `requestPermission()` 再立意图，开定位被挡住时靠这里补上。
    func handleAuthorizationChange(_ status: CLAuthorizationStatus, accuracy: CLAccuracyAuthorization) {
        if authorizationStatus != status {
            authorizationStatus = status
        }
        // 「精确位置」开关的变化也走这个回调（SDK `CLLocationManagerDelegate.h` 原文：
        // 「Invoked when either the authorizationStatus or accuracyAuthorization properties change」）。
        applyAccuracyAuthorization(accuracy)

        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            setLocationError(nil)
            if !updateReasons.isEmpty {
                resumeHardwareUpdates()
            }
        case .denied, .restricted:
            setLocationError(.permissionDenied)
            clearDeviceLocation()
            setEscortLocationMode(.off)
            // 只停硬件、不撤回意图：用户在系统设置里重新打开权限时，原来在跑的定位要恢复。
            haltHardwareUpdates()
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }
}
