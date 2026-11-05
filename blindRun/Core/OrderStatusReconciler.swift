import Combine
import Foundation
import SwiftUI

struct RealtimeOrderStatusUpdate: Equatable, Sendable {
    let messageId: String?
    let orderId: Int64
    let fromStatus: RunOrderStatus
    let toStatus: RunOrderStatus
    let receivedAt: Date

    init(
        messageId: String? = nil,
        orderId: Int64,
        fromStatus: RunOrderStatus,
        toStatus: RunOrderStatus,
        receivedAt: Date
    ) {
        self.messageId = messageId
        self.orderId = orderId
        self.fromStatus = fromStatus
        self.toStatus = toStatus
        self.receivedAt = receivedAt
    }
}

struct OrderStatusRequestToken: Equatable, Sendable {
    let orderID: Int64
    fileprivate let generation: UInt64
}

enum OrderStatusReconciliationResult: Equatable, Sendable {
    case applied(RunOrderStatus)
    case duplicate(RunOrderStatus)
    case rejectedStale(current: RunOrderStatus, candidate: RunOrderStatus)
    case rejectedInvalid(current: RunOrderStatus?, candidate: RunOrderStatus)

    var resolvedStatus: RunOrderStatus? {
        switch self {
        case .applied(let status), .duplicate(let status):
            return status
        case .rejectedStale(let current, _):
            return current
        case .rejectedInvalid(let current, _):
            return current
        }
    }
}

/// Serial, in-memory authority for status candidates from REST and WebSocket.
/// It prevents a request that started before a realtime transition from
/// overwriting the newer state when its response arrives late.
struct OrderStatusReconciler {
    private struct Entry {
        var status: RunOrderStatus
        var generation: UInt64
    }

    private var entries: [Int64: Entry] = [:]

    mutating func register(orderID: Int64, status: RunOrderStatus) {
        guard let current = entries[orderID] else {
            entries[orderID] = Entry(status: status, generation: 0)
            return
        }
        if current.status == status { return }
        if current.status.canReach(status) {
            entries[orderID] = Entry(status: status, generation: current.generation &+ 1)
        }
    }

    mutating func unregister(orderID: Int64) {
        entries.removeValue(forKey: orderID)
    }

    mutating func removeAll() {
        entries.removeAll(keepingCapacity: false)
    }

    func requestToken(orderID: Int64) -> OrderStatusRequestToken {
        OrderStatusRequestToken(
            orderID: orderID,
            generation: entries[orderID]?.generation ?? 0
        )
    }

    func currentStatus(orderID: Int64) -> RunOrderStatus? {
        entries[orderID]?.status
    }

    func isCurrent(_ token: OrderStatusRequestToken) -> Bool {
        (entries[token.orderID]?.generation ?? 0) == token.generation
    }

    mutating func reconcileRealtime(
        orderID: Int64,
        fromStatus: RunOrderStatus,
        toStatus: RunOrderStatus
    ) -> OrderStatusReconciliationResult {
        let current = entries[orderID]?.status
        guard current == nil || current == fromStatus else {
            if current == toStatus { return .duplicate(toStatus) }
            return current.map {
                $0.canReach(fromStatus)
                    ? .rejectedInvalid(current: $0, candidate: toStatus)
                    : .rejectedStale(current: $0, candidate: toStatus)
            } ?? .rejectedInvalid(current: nil, candidate: toStatus)
        }
        guard fromStatus.isDirectlyFollowed(by: toStatus) else {
            return .rejectedInvalid(current: current, candidate: toStatus)
        }

        let nextGeneration = (entries[orderID]?.generation ?? 0) &+ 1
        entries[orderID] = Entry(status: toStatus, generation: nextGeneration)
        return .applied(toStatus)
    }

    mutating func reconcileREST(
        orderID: Int64,
        candidate: RunOrderStatus,
        token: OrderStatusRequestToken
    ) -> OrderStatusReconciliationResult {
        guard token.orderID == orderID else {
            return .rejectedInvalid(current: entries[orderID]?.status, candidate: candidate)
        }
        guard let current = entries[orderID] else {
            entries[orderID] = Entry(status: candidate, generation: 0)
            return .applied(candidate)
        }
        if candidate == current.status { return .duplicate(candidate) }
        // 后端返回了客户端不认识的新状态（#329，安卓 #106 同源）。它没有档位、也没有迁移表可查，
        // 下面的档位闸会把它当成「倒退」丢掉，订单页就停在旧状态、旧按钮还亮着。
        // 令牌没落后、当前不是终态 ⇒ 采纳，落到只读的「状态未知」页；迟到的响应或终态之后照旧拒。
        // 下一个认识的状态会把页面救回来（`.unknown` 的后继一律放行，见 `isDirectlyFollowed`）。
        if candidate == .unknown {
            guard token.generation >= current.generation, !current.status.isTerminal else {
                return .rejectedStale(current: current.status, candidate: candidate)
            }
            entries[orderID] = Entry(status: candidate, generation: current.generation &+ 1)
            return .applied(candidate)
        }
        if current.status.lifecycleRank > candidate.lifecycleRank,
           !candidate.isTerminal,
           candidate != .rematching {
            return .rejectedStale(current: current.status, candidate: candidate)
        }

        if current.status.canReach(candidate) {
            entries[orderID] = Entry(status: candidate, generation: current.generation &+ 1)
            return .applied(candidate)
        }
        if candidate.canReach(current.status) || token.generation < current.generation {
            return .rejectedStale(current: current.status, candidate: candidate)
        }
        return .rejectedInvalid(current: current.status, candidate: candidate)
    }
}

private extension RunOrderStatus {
    var lifecycleRank: Int {
        switch self {
        // `.pendingIntroCall` 与 `.pendingMatch` **同档**，这不是偷懒。
        // 这一档只被 `reconcileREST` 用来拒绝「倒退的」REST 结果，而这两态之间的倒退是真的：
        // 本轮没聊成时后端把订单退回 `PENDING_MATCH`（`IntroCallService.releaseToQueue`，
        // 刻意不是 `REMATCHING`）。给通话态排更高的档，那条真实迁移会被判成陈旧丢掉，
        // 盲人的页面就永远停在「等待通话确认」。
        case .pendingMatch, .pendingIntroCall: return 0
        // 🚩 `.scheduledConfirmed` 与 `.pendingAccept` **同档 1，不能给 0**。
        // `REMATCHING → SCHEDULED_CONFIRMED` 是真实迁移（重新派单后被一张远期单接走，
        // 后端 `OrderStatus.canTransitionTo` 明写），而 `.rematching` 是 1 ——
        // 给 0 会让这条真实迁移被判成「倒退的陈旧结果」丢掉，订单页永远停在「重新匹配中」。
        // 这就是上面那段 `.pendingIntroCall` 注释说的同一个坑，换了个状态而已。
        //
        // 同档的已知代价（与 `.pendingAccept` / `.rematching` 之间那对完全一样，是本设计的既有边界）：
        // 一条陈旧的 REST 结果可以把 `PENDING_ACCEPT` 拉回 `SCHEDULED_CONFIRMED`。
        // 后果只是多显示一次确认按钮，按下去后端返 409，不是不可逆操作。
        case .scheduledConfirmed, .pendingAccept, .rematching: return 1
        case .driverEnRoute: return 2
        case .driverArrived: return 3
        case .inProgress: return 4
        case .completed, .cancelled, .noVolunteer: return 5
        // 排在所有真实状态之前，这样「当前是未知态」永远不会把一个真实状态判成陈旧。
        case .unknown: return -1
        }
    }

    func isDirectlyFollowed(by candidate: RunOrderStatus) -> Bool {
        switch self {
        case .pendingMatch:
            return [.pendingIntroCall, .scheduledConfirmed, .pendingAccept, .cancelled, .noVolunteer].contains(candidate)
        // 后端 `OrderStatus.java` 的通话磨合分支：双方认可 → PENDING_ACCEPT；
        // 任一方不认可 / 没接到 / 窗口超时 → **退回进通话之前那个状态**；
        // 轮次达上限 → NO_VOLUNTEER；盲人取消 → CANCELLED。
        //
        // ⚠️ 「退回之前那个状态」是 2026-08-26 后端修 P0（N105）时改的，此前写死 `PENDING_MATCH`。
        // 所以 `REMATCHING`（志愿者接过单又中途取消、正在重新找人，期间又有人表示有意向）
        // 现在也是一个合法的后继 —— 那条边此前不会出现。
        case .pendingIntroCall:
            return [.scheduledConfirmed, .pendingAccept, .pendingMatch, .rematching,
                    .cancelled, .noVolunteer].contains(candidate)
        // 跨天预约（后端迁移 `0041`）：距开跑超过 240 分钟时被接单的订单落这一态。
        // 出边三条，逐字取自后端 `OrderStatus.canTransitionTo`：临期确认 → `PENDING_ACCEPT`；
        // 闸门到点未确认 / 志愿者取消 → `REMATCHING`；盲人取消 → `CANCELLED`。
        // ⚠️ **没有 `→ NO_VOLUNTEER`** —— 人已经定了，「无人接单」在这一态不是可能的结局。
        case .scheduledConfirmed:
            return [.pendingAccept, .rematching, .cancelled].contains(candidate)
        case .pendingAccept:
            return [.driverEnRoute, .cancelled, .rematching].contains(candidate)
        // 汇合与陪跑三态的出边逐字取自后端 `OrderStatus.canTransitionTo`（#465）：
        // `→ COMPLETED` 是 `autoCompleteOrder` 超时自动完成（在路上 / 已到达也会发生），
        // `→ CANCELLED` 是陪跑员「结束等待」（后端 #362）、跑者到达后取消（后端 #682）、
        // 重匹达上限与 `forceTerminateStuckOrder` 兜底。
        // ⚠️ 这几条边此前不在表里，但 `canReach` 能经 `REMATCHING` / `IN_PROGRESS` 多跳到达，
        // 所以 REST 路径一直是对的、只有 `reconcileRealtime`（只认直接后继）把推送判成非法 ——
        // 首页因此收不到这条推送，陪跑员站在集合点听不到「已取消、可以离开」。
        case .driverEnRoute:
            return [.driverArrived, .completed, .rematching, .cancelled].contains(candidate)
        case .driverArrived:
            return [.inProgress, .completed, .rematching, .cancelled].contains(candidate)
        case .inProgress:
            return [.completed, .rematching, .cancelled].contains(candidate)
        // `REMATCHING` 与 `PENDING_MATCH` 在后端 `isDispatchable()` 下行为一致，
        // 所以它同样能被一个候选人「有意向」拽进通话磨合。
        case .rematching:
            return [.pendingIntroCall, .scheduledConfirmed, .pendingAccept, .cancelled, .noVolunteer].contains(candidate)
        case .completed, .cancelled, .noVolunteer:
            return false
        // 未知态没有任何可信的后继约束，一律放行，让下一个认识的状态把界面救回来。
        // 反方向：`.unknown` 不在 `allCases` 里，`canReach` 的遍历永远到不了它 ——
        // 「已知 → 未知」不走这张表，由 `reconcileREST` 开头那条专门的分支判（#329）。
        case .unknown:
            return true
        }
    }

    func canReach(_ candidate: RunOrderStatus) -> Bool {
        if self == candidate { return true }
        var visited: Set<RunOrderStatus> = [self]
        var pending = [self]
        while let status = pending.popLast() {
            for next in RunOrderStatus.allCases where status.isDirectlyFollowed(by: next) {
                if next == candidate { return true }
                if visited.insert(next).inserted {
                    pending.append(next)
                }
            }
        }
        return false
    }
}
