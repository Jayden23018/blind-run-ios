import Combine
import Foundation
import SwiftUI

enum RealtimePriority: Int, Codable, Comparable, Sendable {
    case normal = 0
    case high = 1

    init(rawValue: String?) {
        self = rawValue?.uppercased() == "HIGH" ? .high : .normal
    }

    static func < (lhs: RealtimePriority, rhs: RealtimePriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum RealtimePeerRole: String, Sendable {
    case blind
    case volunteer
}

struct RealtimePeerLocationSample: Sendable {
    let orderId: Int64
    let ownerRole: RealtimePeerRole
    let latitude: Double
    let longitude: Double
    let timestampMilliseconds: Int64
    /// 定位精度（米）。目前只有 `BLIND_LOCATION_UPDATE` 带（`accuracyM`，可缺省）。
    var accuracyMeters: Double?

    var isValid: Bool {
        (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
}

/// 陪跑员订单页 v2 的两条实时推送。都**不落通知日志**，重连后以订单详情为准，
/// 所以消费方只把它们就地合进手上那份订单，不当权威。
enum RealtimeOrderLiveUpdate: Sendable {
    case eta(orderId: Int64, EtaView)
    case meet(orderId: Int64, MeetView)

    var orderId: Int64 {
        switch self {
        case .eta(let orderId, _), .meet(let orderId, _): return orderId
        }
    }
}

extension OrderDetailResponse {
    /// 把一条实时推送合进这份订单。订单号对不上时原样返回。
    func merging(_ update: RealtimeOrderLiveUpdate) -> OrderDetailResponse {
        guard update.orderId == orderId else { return self }
        var merged = self
        switch update {
        case .eta(_, let eta): merged.eta = eta
        case .meet(_, let meet): merged.meet = meet
        }
        return merged
    }
}

struct RealtimeOrderRefreshRequest: Sendable {
    enum Reason: Sendable { case statusChanged, reconnected }
    let orderId: Int64
    let reason: Reason
}

struct RealtimeDispatchPrompt: Sendable {
    let order: WSNewOrder
    let receivedAt: Date
    let expiresAt: Date

    func remainingSeconds(at date: Date = Date()) -> Int {
        max(0, Int(ceil(expiresAt.timeIntervalSince(date))))
    }
}

struct RealtimeSeparationAlert: Sendable {
    let eventID: String
    let orderID: Int64
    let eventType: String
    let distanceMeters: Double?
    let displayText: String
    let speechText: String
    let timestamp: String?
}

struct RealtimeSafetyEvent: Sendable {
    enum Kind: String, Sendable {
        case emergencyVolunteerAlert
        case emergencyResolved
        case emergencyContactNotified
        // The ones below reach iOS as `APP_NOTIFICATION` envelopes carrying an `eventType`, not as
        // top-level WebSocket types (`NotificationService.sendNotification`, :93-99).
        case emergencyTriggered
        case emergencyNoContact
        case emergencyVolunteerTimeout
        // 2026-07-31 batch (handoff.md): volunteer-initiated SOS, SMS delivery receipts, and the
        // close-out events that previously left the blind runner with zero notification.
        case emergencyTriggeredByVolunteer
        case emergencyContactSmsDelivered
        case emergencyContactNotifyFailed
        case emergencyVolunteerAck
        case emergencyClosedResolved
        case emergencyClosedFalseAlarm

        /// Kinds that mean "an emergency involving this user is open right now". Used to decide
        /// whether an event arriving with no local state is worth a recovery fetch — close-out and
        /// observer events are not, so a resolved event never resurrects itself.
        var impliesLiveEmergency: Bool {
            switch self {
            case .emergencyTriggered, .emergencyTriggeredByVolunteer, .emergencyContactNotified,
                 .emergencyContactSmsDelivered, .emergencyContactNotifyFailed, .emergencyNoContact,
                 .emergencyVolunteerTimeout, .emergencyVolunteerAck:
                return true
            case .emergencyResolved, .emergencyClosedResolved, .emergencyClosedFalseAlarm,
                 .emergencyVolunteerAlert:
                return false
            }
        }
    }

    let eventID: String
    let orderID: Int64?
    let kind: Kind
    let displayText: String
    let speechText: String
    let timestamp: String?
    /// 受助者触发求助那一刻的位置。**只有 `EMERGENCY_VOLUNTEER_ALERT` 带得出来**
    /// （`websocket-protocol.md:546` 的 `gpsLat`/`gpsLng`，可为 null），其余
    /// `EMERGENCY_*` 走 `APP_NOTIFICATION` 信封，连 `eventId` 都没有。
    ///
    /// 已经过 `BackendCoordinateNormalizer` 归一 —— 后端给的是 GCJ-02，
    /// 而本仓库只允许坐标在**单一边界**上转换一次（`AGENTS.md` §3）。
    /// 这里不转的话，志愿者端算出来的「距他多远」会带上几百米的坐标系偏移。
    let coordinate: LocatedCoordinate?
    /// 服务端算的两人距离，只在档位可用时才有（`WSEmergencyVolunteerAlert.fallbackDistanceMeters`）。
    /// 本机 GPS 还冷着时的兜底，见 `VolunteerEmergencyAlert.distanceText(from:)`。
    var serverDistanceMeters: Double? = nil
}

struct RealtimeRecoverySignal: Sendable {
    let role: WSRole
    let connectedAt: Date
}
