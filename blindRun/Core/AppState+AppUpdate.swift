import Foundation

extension AppState: AppUpdateSource {
    func appVersionRequirements() async throws -> AppVersionResponse {
        try await auth.appVersionRequirements()
    }

    /// 本地已知的事实排在前面：跑步中登录过期时查不了订单，而那正是最不能挡住的时刻（#376）。
    func appUpdateOrderPresence() async -> AppUpdateOrderPresence {
        if isSessionExpiryDeferred
            || liveEscortCoordinator.isSessionEligible
            || emergencyCoordinator.activeEvent != nil
            || emergencyCoordinator.volunteerAlert != nil {
            return .underway
        }
        // 恢复中还不知道这是谁、有没有在跑。恢复结束时根视图会再检查一次。
        switch sessionRestorationState {
        case .restoring, .validationFailed:
            return .unknown
        case .unauthenticated, .choosingRole:
            return .none
        case .authenticated:
            break
        }
        do {
            switch activeRole {
            case .blind:
                let status = try await orders.activeOrder().data?.status
                return Self.orderPresence(statuses: status.map { [$0] } ?? [])
            case .volunteer:
                // 后端这个列表的白名单正好是同行三态（`VolunteerService.loadActiveOrders`）。
                guard let activeOrders = try await orders.dispatchSummary().activeOrders else { return .unknown }
                return Self.orderPresence(statuses: activeOrders.map(\.status))
            case .unset, nil:
                return .unknown
            }
        } catch {
            ClientFlowDiagnostics.record(event: "failed", operation: "app-update-order-presence")
            return .unknown
        }
    }

    /// 判据就是 `isEscortUnderway`。客户端不认识的新状态算查不清：不能断定他没在跑。
    static func orderPresence(statuses: [RunOrderStatus]) -> AppUpdateOrderPresence {
        if statuses.contains(where: \.isEscortUnderway) { return .underway }
        return statuses.contains(.unknown) ? .unknown : .none
    }
}
