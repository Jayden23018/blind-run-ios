import Foundation
import UserNotifications

/// 邀请类 APNs 的锁屏操作（后端 #369 #370，契约 `websocket-protocol.md`「邀请类 APNs」，iOS #338）。
///
/// category、操作 id、自定义键名都**以契约为准**，这里不自己起名：
/// - `INVITE`（`requiresIntroCall = false`）：「接下」+「这次去不了」
/// - `INVITE_INTRO_CALL`（要先通话）：只有「这次去不了」—— 锁屏「接下」会被 409 `INTRO_CALL_REQUIRED` 拒，用户看不到反馈
///
/// 两个操作都要解锁（后端 #369 答复），**都拉起 App**，回复走邀请卡上同一条路径：
/// - 「接下」要过定位权限闸、可能被 409 改发 `INTERESTED`、成功后卡片原地变「已约好」；
/// - 「这次去不了」走带 5 秒撤销的 `declineInvite`，有可听可见的回执；
/// - 只回复**当前账号队列里还在等回复的那一张**：换了账号、旧通知已过期、同一单换了新邀请，都对不上，不会替别人回复；
/// - 不依赖后台拉起（那时根视图未必加载、会话可能还没恢复，回复会静默丢失 —— #338 安全复核 HIGH 2）。
enum InviteNotificationActions {
    static let inviteCategory = "INVITE"
    static let introCallCategory = "INVITE_INTRO_CALL"
    static let acceptAction = "ACCEPT_INVITE"
    static let declineAction = "DECLINE_INVITE"
    /// 带这两种 `eventType` 的 APNs 是邀请（契约：与 WS 信封同一套常量）。
    static let inviteEventTypes: Set<String> = ["NEW_ORDER", "INVITE_EXPIRING"]

    static var categories: Set<UNNotificationCategory> {
        let accept = UNNotificationAction(
            identifier: acceptAction,
            title: VolunteerOrderFlowCopy.acceptInvite,
            options: [.authenticationRequired, .foreground]
        )
        let decline = UNNotificationAction(
            identifier: declineAction,
            title: VolunteerOrderFlowCopy.declineInvite,
            options: [.authenticationRequired, .foreground, .destructive]
        )
        return [
            UNNotificationCategory(identifier: inviteCategory, actions: [accept, decline], intentIdentifiers: []),
            UNNotificationCategory(identifier: introCallCategory, actions: [decline], intentIdentifiers: []),
        ]
    }

    enum Action: Equatable, Sendable {
        case accept
        case decline
    }

    /// 锁屏上按下的一个邀请操作。
    struct Request: Equatable, Sendable {
        let action: Action
        let invite: InviteIdentity
    }

    /// 不是邀请操作（点通知本身、别的 category、单号缺失或不合法）返回 `nil`。
    static func request(actionIdentifier: String, userInfo: [AnyHashable: Any]) -> Request? {
        let action: Action
        switch actionIdentifier {
        case acceptAction: action = .accept
        case declineAction: action = .decline
        default: return nil
        }
        guard let invite = InviteIdentity(userInfo: userInfo) else { return nil }
        return Request(action: action, invite: invite)
    }

    /// 这条推送是不是邀请（`NEW_ORDER` / `INVITE_EXPIRING`）。
    static func isInviteEvent(_ userInfo: [AnyHashable: Any]) -> Bool {
        (userInfo["eventType"] as? String).map(inviteEventTypes.contains) ?? false
    }

    /// 前台收到时交给 App 内呈现、系统横幅不出的那一类：**只有 `NEW_ORDER`** —— 同一条邀请 WS 也会到，App 内的邀请卡
    /// 才是它在前台的样子。`INVITE_EXPIRING` 照旧弹出：App 不处理 WS 那一条（#344 定的），吞掉它前台就什么提醒都没有。
    static func isForegroundDuplicate(_ userInfo: [AnyHashable: Any]) -> Bool {
        (userInfo["eventType"] as? String) == "NEW_ORDER"
    }

    /// 前台收到推送时系统该怎么呈现：`NEW_ORDER` 什么都不出（交给 App 内），其余照旧横幅加提示音。
    static func foregroundPresentationOptions(for userInfo: [AnyHashable: Any]) -> UNNotificationPresentationOptions {
        isForegroundDuplicate(userInfo) ? [] : [.banner, .sound]
    }
}

/// 一张邀请的身份：单号必有；`inviteId` 只有 `INVITE_EXPIRING` 的 APNs 带（`NEW_ORDER` 那条没有，契约原话）；
/// `expiresAt` 两种 APNs 都带。同一单撤回后的**新**邀请有新 `inviteId` 与新 `expiresAt`，靠它们与旧的分开。
struct InviteIdentity: Equatable, Sendable {
    let orderId: Int64
    let inviteId: Int64?
    let expiresAt: Date?

    init(orderId: Int64, inviteId: Int64?, expiresAt: Date?) {
        self.orderId = orderId
        self.inviteId = inviteId
        self.expiresAt = expiresAt
    }

    /// 从推送载荷取。单号必须是正整数（拒绝布尔、小数、0、负数：拼进 `/respond` 的路径之前就挡掉）。
    init?(userInfo: [AnyHashable: Any]) {
        guard let orderId = Self.positiveID(userInfo["orderId"]) else { return nil }
        self.init(
            orderId: orderId,
            inviteId: Self.positiveID(userInfo["inviteId"]),
            expiresAt: (userInfo["expiresAt"] as? String)?.backendTimestamp
        )
    }

    /// 是不是同一张：单号相同，且两边都有 `inviteId` 时它相同，否则两边都有期限时期限相同（差 1 秒以内）；
    /// 都对不上细节时只按单号认（老服务端 / 测试种子）。
    func matches(orderId otherOrderId: Int64, inviteId otherInviteId: Int64?, expiresAt otherExpiresAt: Date?) -> Bool {
        guard orderId == otherOrderId else { return false }
        if let inviteId, let otherInviteId { return inviteId == otherInviteId }
        if let expiresAt, let otherExpiresAt { return abs(expiresAt.timeIntervalSince(otherExpiresAt)) < 1 }
        return true
    }

    func matches(_ other: InviteIdentity) -> Bool {
        matches(orderId: other.orderId, inviteId: other.inviteId, expiresAt: other.expiresAt)
    }

    /// 契约说单号是数字；字符串也认，免得后端换一次序列化就整条操作静默失效。
    private static func positiveID(_ value: Any?) -> Int64? {
        if let number = value as? NSNumber {
            guard CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue == Double(number.int64Value) else { return nil }
            return number.int64Value > 0 ? number.int64Value : nil
        }
        if let text = value as? String, let id = Int64(text), id > 0, String(id) == text { return id }
        return nil
    }
}

// MARK: - 已送达的邀请通知

/// 要从通知中心收掉哪些邀请通知（撤回推送不会销毁锁屏上那条，契约要客户端自己收）。
enum InviteNotificationPrune: Equatable, Sendable {
    /// 这几张邀请的通知（被撤回、本地已了结）。**按邀请身份收，不按整单收**：同一单可能已经有一张新邀请。
    case invites([InviteIdentity])
    /// 待回复快照：不在快照里、且早于这次请求送达的（请求在路上时到的新邀请不在快照里，不能收）。
    case allExcept(Set<Int64>, deliveredBefore: Date)
}

struct DeliveredInviteNotification: Equatable, Sendable {
    let identifier: String
    let invite: InviteIdentity
    let date: Date
}

extension InviteNotificationActions {
    /// 已送达的一条通知是不是邀请；是就取出它的邀请身份。
    static func deliveredInvite(identifier: String, date: Date, userInfo: [AnyHashable: Any]) -> DeliveredInviteNotification? {
        guard isInviteEvent(userInfo), let invite = InviteIdentity(userInfo: userInfo) else { return nil }
        return DeliveredInviteNotification(identifier: identifier, invite: invite, date: date)
    }

    static func identifiersToRemove(_ delivered: [DeliveredInviteNotification], _ prune: InviteNotificationPrune) -> [String] {
        delivered.filter { note in
            switch prune {
            case .invites(let invites): return invites.contains { $0.matches(note.invite) }
            case .allExcept(let ids, let before): return !ids.contains(note.invite.orderId) && note.date < before
            }
        }.map(\.identifier)
    }
}

/// 真的去动系统通知中心的那一半。单测不走这里（协调器默认的收通知钩子是空的，由 `PushNotificationsManager` 接上）。
enum InviteNotificationCenter {
    static func prune(_ prune: InviteNotificationPrune) async {
        let center = UNUserNotificationCenter.current()
        let delivered = await center.deliveredNotifications().compactMap {
            InviteNotificationActions.deliveredInvite(
                identifier: $0.request.identifier, date: $0.date, userInfo: $0.request.content.userInfo
            )
        }
        let identifiers = InviteNotificationActions.identifiersToRemove(delivered, prune)
        guard !identifiers.isEmpty else { return }
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}
