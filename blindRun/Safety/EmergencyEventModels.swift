import CoreLocation
import Foundation

// 从 `EmergencyCoordinator.swift` 原样搬来（#506）：那个文件已超 SwiftLint 长度上限，CI 棘轮不许再变长。

/// One in-flight or acknowledged SOS. Deliberately separate from `RunOrderStatus`: an emergency
/// event never mutates the order lifecycle (`AGENTS.md` section 6).
struct ActiveEmergencyEvent: Equatable, Sendable {
    let eventID: Int64
    let orderID: Int64
    /// Authenticated user the event belongs to. Guards against presenting one account's emergency
    /// under another after a role switch or re-login.
    let userID: Int64?
    var status: EmergencyEventStatus
}

/// An `EMERGENCY_VOLUNTEER_ALERT` addressed to the escorting volunteer as observer.
///
/// The volunteer's only possible answer is "确认需要帮助". There is deliberately no dismiss action:
/// `action=FALSE_ALARM` is a hard 403 server-side, because in a one-to-one escort the companion is
/// the person a victim may need protection from.
struct VolunteerEmergencyAlert: Equatable, Sendable {
    let eventID: Int64
    let orderID: Int64?
    let message: String
    /// 受助者触发那一刻的位置（已归一到 GCJ-02）。可为 nil —— 契约里那两个字段各自可空，
    /// 而「盲人当时拿不到定位」在室内 / 高楼间是常态，不是异常。
    var coordinate: LocatedCoordinate?
    /// 收到这条告警的本机时刻。屏 5 上那句「X 秒前」读的是它。
    ///
    /// **不用后端的 `timestamp`**：那是服务端时钟，而两端时钟可能差几秒到几分钟，
    /// 差出来的结果是屏幕上写着「-40 秒前」或者「3 分钟前」——
    /// 而志愿者正据此判断「这事刚发生还是我漏看了很久」。
    let receivedAt: Date
    var isAcknowledged = false
    /// 服务端算的两人距离（只在档位可用时才有）。本机定位拿不到时的兜底 ——
    /// 锁屏推送刚把手机唤醒、GPS 还冷着的那几秒，恰恰是这条告警最常见的到达场景。
    var serverDistanceMeters: Double?

    init(
        eventID: Int64,
        orderID: Int64?,
        message: String,
        coordinate: LocatedCoordinate? = nil,
        receivedAt: Date = Date(),
        isAcknowledged: Bool = false,
        serverDistanceMeters: Double? = nil
    ) {
        self.eventID = eventID
        self.orderID = orderID
        self.message = message
        self.coordinate = coordinate
        self.receivedAt = receivedAt
        self.isAcknowledged = isAcknowledged
        self.serverDistanceMeters = serverDistanceMeters
    }

    /// 「距你多远」，只给分档（`DistanceCalculator.proximityBand`），不给精确数字。
    ///
    /// 本机实时定位优先 —— 服务端那份用的是志愿者最近一次上报，最旧可能 30 秒。
    /// 两份都没有就返回 nil、整行不显示，**不猜**：「就在附近」会让他以为人就在脚边。
    func distanceText(from device: CLLocationCoordinate2D?) -> String? {
        let meters: CLLocationDistance
        if let peer = coordinate, let device {
            meters = DistanceCalculator.distanceFromDeviceToBackend(
                deviceCoordinate: device,
                backendCoordinate: peer.coordinate
            )
        } else if let serverDistanceMeters {
            meters = serverDistanceMeters
        } else {
            return nil
        }
        return "距你\(DistanceCalculator.proximityBand(meters))"
    }
}
