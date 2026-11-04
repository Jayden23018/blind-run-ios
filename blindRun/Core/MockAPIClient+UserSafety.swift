//
//  MockAPIClient+UserSafety.swift
//  blindRun
//
//  举报与拉黑的进程内 Mock（OpenSpec `add-user-report-and-block`）。
//

import Foundation

extension MockAPIClient {
    static let mockReportTicket = UserReportTicket(id: 2026)

    /// `GET /api/support/tickets` 的回放：一条已回复、一条刚收到，最近的在前。
    /// 回复文字故意不带任何时限或「回拨」，Mock 不该演后端也不会发的承诺。
    static let mockSupportTickets = SupportTicketPage(content: [
        SupportTicketSummary(
            id: 3002,
            content: "上次陪跑的时间和约好的不一样，想问一下是怎么回事。",
            status: .open,
            createdAt: "2026-11-03T20:15:00"
        ),
        SupportTicketSummary(
            id: 3001,
            content: "登录时一直收不到验证码。",
            status: .replied,
            csReply: "已经帮你检查过，验证码可以正常发送了，请再试一次。",
            createdAt: "2026-11-01T09:30:00",
            repliedAt: "2026-11-01T14:05:00"
        )
    ])

    /// 不是这三条路径时返回 nil，交回主路由。Mock 不演「没有交集」的 404：那条分支由替身用例守。
    func routeUserBlock(method: HTTPMethod, path: String) -> Any? {
        if path == "/api/users/blocked" && method == .get {
            return SkippingUndecodable(wrappedValue: blockedUsers)
        }
        guard path.hasPrefix("/api/users/"), path.hasSuffix("/block") else { return nil }
        let id = path.dropFirst("/api/users/".count).dropLast("/block".count)
        guard let userId = Int64(id) else { return nil }
        switch method {
        case .post:
            if !blockedUsers.contains(where: { $0.userId == userId }) {
                let user = BlockedUserResponse(
                    userId: userId,
                    maskedName: Self.mockOrderVolunteerName,
                    blockedAt: "2026-11-02T09:30:00"
                )
                blockedUsers.insert(user, at: 0)
            }
            return EmptyResponse()
        case .delete:
            blockedUsers.removeAll { $0.userId == userId }
            return EmptyResponse()
        default:
            return nil
        }
    }
}
