import CoreMotion
import Foundation

// 本机在一单跑步里的步数 / 步频 / 相对海拔（DECISIONS D3、D10；OpenSpec `add-post-run-record`）。
// 两台手机各采各的，随同行会话的 `LOCATION_UPDATE` 上报，后端按角色分别计算。
//
// CoreMotion 的三条事实决定了这里的形状（本机 iPhoneOS 26.2 SDK 头文件，2026-09-24 核实）：
// - `CMPedometer.startUpdates(from:)` 给的是**从 from 起的累计值**，App 被挂起期间的步数下一次回调补齐，
//   历史保留 7 天 ⇒ 只要起点不变，重启 App 也不会归零。起点因此按订单持久化。
// - `currentCadence` 单位是**步/秒**，拿不到时为 nil ⇒ 上报前 ×60，nil 就不传。
// - `CMAltimeter` 的相对海拔**以第一次回调为 0** ⇒ 重启后会从 0 重来。用上次报过的值做基线续上，
//   否则一次「−8 → 0」的跳变会被后端算成 8 米爬升。

/// 这一刻要随位置一起上报的运动数据。每个字段都可能没有 —— 没有就不传，绝不传 0。
nonisolated struct RunMotionSnapshot: Equatable, Sendable {
    /// 本次跑步起的累计步数。
    var steps: Int?
    /// 步/分钟。
    var cadence: Int?
    /// 相对海拔（米），已加上续接基线。
    var altitude: Double?

    /// `CMPedometerData.currentCadence`（步/秒）→ 契约的步/分钟。
    static func cadencePerMinute(fromStepsPerSecond value: Double?) -> Int? {
        guard let value, value >= 0 else { return nil }
        return Int((value * 60).rounded())
    }
}

/// 同行会话持有的运动采集口。协议只为让单测注入假实现 —— 真实现碰的是硬件和系统权限框。
@MainActor
protocol RunMotionRecording: AnyObject {
    var latestSnapshot: RunMotionSnapshot? { get }
    /// 权限还没决定时弹一次系统框；已决定（含拒绝）什么都不做。
    func requestAuthorizationIfNeeded()
    /// 幂等：同一单重复调用不重启。
    func start(orderID: Int64)
    func stop()
}

/// 一单跑步的起点锚。只存一条：同一时刻只会有一单在跑，下一单开跑时直接覆盖。
nonisolated struct RunMotionAnchor: Codable, Equatable, Sendable {
    let orderID: Int64
    let startedAt: Date
    var lastAltitude: Double?
}

nonisolated enum RunMotionAnchorStore {
    static let key = "aidrun.runMotionAnchor"

    /// 同一单返回已存的锚（重启 App 后接着算），换单则以 `now` 为起点新建并存下。
    static func anchor(for orderID: Int64, now: Date, defaults: UserDefaults) -> RunMotionAnchor {
        if let stored = load(defaults), stored.orderID == orderID {
            return stored
        }
        let fresh = RunMotionAnchor(orderID: orderID, startedAt: now, lastAltitude: nil)
        save(fresh, defaults)
        return fresh
    }

    static func recordAltitude(_ altitude: Double, orderID: Int64, defaults: UserDefaults) {
        guard var stored = load(defaults), stored.orderID == orderID else { return }
        stored.lastAltitude = altitude
        save(stored, defaults)
    }

    private static func load(_ defaults: UserDefaults) -> RunMotionAnchor? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(RunMotionAnchor.self, from: $0) }
    }

    private static func save(_ anchor: RunMotionAnchor, _ defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(anchor) { defaults.set(data, forKey: key) }
    }
}

@MainActor
final class CoreMotionRunRecorder: RunMotionRecording {
    private(set) var latestSnapshot: RunMotionSnapshot?

    private let pedometer = CMPedometer()
    private let altimeter = CMAltimeter()
    private let defaults: UserDefaults
    private var activeOrderID: Int64?
    private var didRequestAuthorization = false

    nonisolated init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 🔴 单测宿主里绝不碰硬件、不弹权限框。判据与 `RunLiveActivityController.isRunningUnderXCTest`
    /// 同一条（那个类限 iOS 16.2+，这里不能直接引用）；理由也同：`LiveEscortTrackTests` 大量把会话推进
    /// `IN_PROGRESS`，而单测宿主就是用户手机上的 App 进程。
    private var isHardwareAllowed: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    }

    func requestAuthorizationIfNeeded() {
        guard isHardwareAllowed, !didRequestAuthorization,
              CMPedometer.isStepCountingAvailable(),
              CMPedometer.authorizationStatus() == .notDetermined else { return }
        didRequestAuthorization = true
        // 零长度查询只为触发系统权限框；结果不用。
        let now = Date()
        pedometer.queryPedometerData(from: now, to: now) { @Sendable _, _ in }
    }

    func start(orderID: Int64) {
        guard isHardwareAllowed, activeOrderID != orderID else { return }
        stop()
        activeOrderID = orderID
        latestSnapshot = RunMotionSnapshot()
        let anchor = RunMotionAnchorStore.anchor(for: orderID, now: Date(), defaults: defaults)

        if CMPedometer.isStepCountingAvailable(), Self.isAuthorizedOrUndecided(CMPedometer.authorizationStatus()) {
            pedometer.startUpdates(from: anchor.startedAt) { @Sendable [weak self] data, _ in
                guard let data else { return }
                let steps = data.numberOfSteps.intValue
                let cadence = RunMotionSnapshot.cadencePerMinute(fromStepsPerSecond: data.currentCadence?.doubleValue)
                Task { @MainActor [weak self] in
                    guard let self, self.activeOrderID == orderID else { return }
                    self.latestSnapshot?.steps = steps
                    self.latestSnapshot?.cadence = cadence
                }
            }
        }

        if CMAltimeter.isRelativeAltitudeAvailable(), Self.isAuthorizedOrUndecided(CMAltimeter.authorizationStatus()) {
            let baseline = anchor.lastAltitude ?? 0
            altimeter.startRelativeAltitudeUpdates(to: .main) { @Sendable [weak self] data, _ in
                guard let data else { return }
                let altitude = baseline + data.relativeAltitude.doubleValue
                Task { @MainActor [weak self] in
                    guard let self, self.activeOrderID == orderID else { return }
                    self.latestSnapshot?.altitude = altitude
                    RunMotionAnchorStore.recordAltitude(altitude, orderID: orderID, defaults: self.defaults)
                }
            }
        }
    }

    func stop() {
        guard activeOrderID != nil else { return }
        activeOrderID = nil
        latestSnapshot = nil
        pedometer.stopUpdates()
        altimeter.stopRelativeAltitudeUpdates()
    }

    private static func isAuthorizedOrUndecided(_ status: CMAuthorizationStatus) -> Bool {
        status == .authorized || status == .notDetermined
    }
}
