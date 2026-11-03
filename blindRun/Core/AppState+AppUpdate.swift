import Foundation

extension AppState: AppUpdateSource {
    func appVersionRequirements() async throws -> AppVersionResponse {
        try await auth.appVersionRequirements()
    }

    /// 本地已知的事实排在前面：跑步中登录过期时查不了订单，而那正是最不能盖住的时刻（#376）。
    func appUpdateOrderPresence() async -> AppUpdateOrderPresence {
        if isSessionExpiryDeferred
            || liveEscortCoordinator.isSessionEligible
            || emergencyCoordinator.activeEvent != nil
            || emergencyCoordinator.volunteerAlert != nil {
            return .active
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
                return Self.orderPresence(runnerStatus: try await orders.activeOrder().data?.status)
            case .volunteer:
                return Self.orderPresence(volunteerSummary: try await orders.dispatchSummary())
            case .unset, nil:
                return .unknown
            }
        } catch {
            ClientFlowDiagnostics.record(event: "failed", operation: "app-update-order-presence")
            return .unknown
        }
    }

    /// `.unknown` 状态（客户端不认识的新状态）在 `isActiveForBlindRunner` 里判 true：不把它当成已结束。
    static func orderPresence(runnerStatus: RunOrderStatus?) -> AppUpdateOrderPresence {
        runnerStatus?.isActiveForBlindRunner == true ? .active : .none
    }

    /// 三个字段合起来才是陪跑员手上的全部订单，见 `VolunteerDispatchSummaryResponse` 各字段的注释。
    /// `upcomingOrders` 为 `nil` 表示服务端这一块没取到，不是没有。
    static func orderPresence(volunteerSummary summary: VolunteerDispatchSummaryResponse) -> AppUpdateOrderPresence {
        if summary.activeOrders?.isEmpty == false || summary.introCallOrderId != nil || summary.upcomingOrders?.isEmpty == false {
            return .active
        }
        return summary.upcomingOrders == nil ? .unknown : .none
    }
}
