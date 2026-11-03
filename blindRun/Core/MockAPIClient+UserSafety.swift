//
//  MockAPIClient+UserSafety.swift
//  blindRun
//
//  举报与拉黑的进程内 Mock（OpenSpec `add-user-report-and-block`）。
//

import Foundation

extension MockAPIClient {
    static let mockReportTicket = UserReportTicket(id: 2026)

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
