import Foundation
import UserNotifications

/// 邀请类 APNs 的锁屏操作（后端 #369 #370，契约 `websocket-protocol.md`「邀请类 APNs」，iOS #338）。
///
/// category、操作 id、自定义键名都**以契约为准**，这里不自己起名：
/// - `INVITE`（`requiresIntroCall = false`）：「接下」+「这次去不了」
/// - `INVITE_INTRO_CALL`（要先通话）：只有「这次去不了」—— 锁屏「接下」会被 409 `INTRO_CALL_REQUIRED` 拒，用户看不到反馈
///
/// 两个操作都要解锁（后端 #369 答复）。「接下」另外**拉起 App**：接单要过定位权限闸、可能被 409 改发 `INTERESTED`、
/// 成功后卡片原地变「已约好」—— 这些都在 App 里卡片上那条路径上，锁屏上另写一条就是第二个来源。
/// 「这次去不了」在后台直接回复，409 用一条本地通知说明（契约：给对应说明，不给通用报错）。
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
            options: [.authenticationRequired, .destructive]
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
        let orderId: Int64
        /// 只有 `INVITE_EXPIRING` 的 APNs 带；`NEW_ORDER` 那条没有，按 `orderId` 认（契约原话）。
        let inviteId: Int64?
        /// 回复最晚时刻。用来让「已了结」记录活到这一刻为止。
        let expiresAt: Date?
    }

    /// 不是邀请操作（点通知本身、别的 category、缺 `orderId`）返回 `nil`。
    static func request(actionIdentifier: String, userInfo: [AnyHashable: Any]) -> Request? {
        let action: Action
        switch actionIdentifier {
        case acceptAction: action = .accept
        case declineAction: action = .decline
        default: return nil
        }
        guard let orderId = int64(userInfo["orderId"]) else { return nil }
        return Request(
            action: action,
            orderId: orderId,
            inviteId: int64(userInfo["inviteId"]),
            expiresAt: (userInfo["expiresAt"] as? String)?.backendTimestamp
        )
    }

    /// 这条推送是不是邀请（`NEW_ORDER` / `INVITE_EXPIRING`）。
    static func isInviteEvent(_ userInfo: [AnyHashable: Any]) -> Bool {
        (userInfo["eventType"] as? String).map(inviteEventTypes.contains) ?? false
    }

    /// 回复被 409 拒时那句说明：标题 + 原因，与 App 里那张「已失效」卡同一套字。其余错误给一句「打开 App 再试」。
    static func failureExplanation(for code: ErrorCode?) -> (title: String, body: String) {
        switch code {
        case .orderAlreadyAccepted:
            return (VolunteerInviteCopy.expiredTitle, VolunteerInviteCopy.withdrawnDetail(.taken))
        case .orderDispatchMismatch:
            return (VolunteerInviteCopy.expiredTitle, VolunteerInviteCopy.expiredDetail)
        default:
            return ("没能回复这个邀请", "请打开 App 再试一次")
        }
    }

    /// 契约说 `orderId` 是数字；字符串也认，免得后端换一次序列化就整条操作静默失效。
    private static func int64(_ value: Any?) -> Int64? {
        if let number = value as? NSNumber { return number.int64Value }
        if let text = value as? String { return Int64(text) }
        return nil
    }
}

// MARK: - 已送达的邀请通知

/// 要从通知中心收掉哪些邀请通知（撤回推送不会销毁锁屏上那条，契约要客户端自己收）。
enum InviteNotificationPrune: Equatable, Sendable {
    /// 这几张单的邀请通知（被撤回、本地已回复）。
    case orders(Set<Int64>)
    /// 待回复快照：不在快照里、且早于这次请求送达的（请求在路上时到的新邀请不在快照里，不能收）。
    case allExcept(Set<Int64>, deliveredBefore: Date)
}

struct DeliveredInviteNotification: Equatable, Sendable {
    let identifier: String
    let orderId: Int64
    let date: Date
}

extension InviteNotificationActions {
    /// 已送达的一条通知是不是邀请；是就取出它的单号。
    static func deliveredInvite(identifier: String, date: Date, userInfo: [AnyHashable: Any]) -> DeliveredInviteNotification? {
        guard isInviteEvent(userInfo), let orderId = int64(userInfo["orderId"]) else { return nil }
        return DeliveredInviteNotification(identifier: identifier, orderId: orderId, date: date)
    }

    static func identifiersToRemove(_ delivered: [DeliveredInviteNotification], _ prune: InviteNotificationPrune) -> [String] {
        delivered.filter { note in
            switch prune {
            case .orders(let ids): return ids.contains(note.orderId)
            case .allExcept(let ids, let before): return !ids.contains(note.orderId) && note.date < before
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

    /// App 不在前台时用一条本地通知把回复结果说出来。**不带地址、姓名、手机号**（同邀请 APNs 的锁屏口径）。
    static func post(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: "invite-reply-\(UUID().uuidString)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
