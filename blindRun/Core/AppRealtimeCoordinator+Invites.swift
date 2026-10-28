import Foundation

// 派单邀请在协调器里的值类型与纯函数（后端 #371 / #366）。从 `AppRealtimeCoordinator.swift` 挪出：
// 那个文件与类体只许变短（SwiftLint 棘轮 #488）。改队列本身的函数仍在协调器文件里（要动 private 状态）。

struct RealtimeInviteWithdrawal: Equatable, Sendable {
    let orderId: Int64
    /// `nil` = 推送没带 / 是按快照判的，那时只按 `orderId` 认。
    let inviteId: Int64?
    let reason: InviteWithdrawReason
}

struct RealtimePendingInviteSnapshot: Sendable {
    let invites: [WSNewOrder]
    /// 请求发出的时刻。只有比它更早收到的邀请才能按「快照里没有」判失效。
    let requestedAt: Date

    /// 这张卡在快照里还算不算待回复。
    func contains(orderID: Int64, inviteID: Int64?) -> Bool {
        invites.contains { invite in
            invite.orderId == orderID
                && (inviteID == nil || invite.inviteId == nil || invite.inviteId == inviteID)
        }
    }
}

/// 本地已经了结的邀请（回复过、收起、撤回、失效），记到它原本的回复期限为止。
///
/// 存在的理由：「本地已经回复、后端还没收到」这段时间里（「去不了」有 5 秒撤销窗口才真正发出），
/// 待回复快照里仍有这一张。没有这份记录，回前台 / 重连的一次对账就会把它当成新邀请灌回来 ——
/// 卡片重新弹出，撤销时同一张单还会出现两张卡。撤回同理：早于撤回发出的快照回来时还带着它。
struct RetiredInviteLedger {
    /// 没有期限可参照时的保留时长 = 最长的回复窗口（后端 60 分钟档）。
    static let fallbackLifetime: TimeInterval = 60 * 60

    private struct Key: Hashable {
        let orderID: Int64
        /// `nil` = 老服务端 / 测试种子，没有邀请身份：同一张单的任何邀请都算它。
        let inviteID: Int64?
    }

    private var entries: [Key: Date] = [:]

    /// 记下一张。顺手清掉已经过期的记录。
    mutating func retire(orderID: Int64, inviteID: Int64?, until: Date?, now: Date) {
        entries = entries.filter { $0.value > now }
        entries[Key(orderID: orderID, inviteID: inviteID)] = until ?? now.addingTimeInterval(Self.fallbackLifetime)
    }

    /// 这张邀请是不是本地已经了结过。期限过了的记录不算。
    func contains(_ message: WSNewOrder, now: Date) -> Bool {
        entries.contains { key, until in
            until > now
                && key.orderID == message.orderId
                && (key.inviteID == nil || message.inviteId == nil || key.inviteID == message.inviteId)
        }
    }
}

extension AppRealtimeCoordinator {
    /// 回复期限。**以 `expiresAt` 为准**（契约：「权威字段……不要自己拿 `dispatchTimeoutSeconds` 加当前时间推」）；
    /// 老服务端没有它时才退回「发出时刻 + 秒数」；两样都没有时按 30 秒（旧行为）。
    ///
    /// ⚠️ 读 `expiresAt` 意味着倒计时跟着手机时钟走（拿后端的绝对时刻与本机现在比）。期限是 15 / 60 分钟，
    /// 联网手机的时钟误差在秒级，可以接受；而 REST 快照恢复回来的邀请也只有这一个绝对时刻可用。
    static func dispatchExpiry(_ message: WSNewOrder, receivedAt: Date) -> Date {
        if let server = message.expiresAt?.nilIfBlank?.backendTimestamp { return server }
        // 两样都没有时沿用旧行为的 30 秒（串行派单时代的默认窗口），而不是整条丢掉。
        let timeout = message.dispatchTimeoutSeconds ?? 30
        let sentAt = parseISO8601(message.timestamp) ?? receivedAt
        return sentAt.addingTimeInterval(TimeInterval(max(0, timeout)))
    }

    /// 两条消息是不是**不同的两张**邀请。任一边没有 `inviteId`（老服务端）时按同一张算，退回按 `orderId` 去重。
    nonisolated static func isDifferentInvite(_ existing: WSNewOrder, _ incoming: WSNewOrder) -> Bool {
        guard let old = existing.inviteId, let new = incoming.inviteId else { return false }
        return old != new
    }
}
