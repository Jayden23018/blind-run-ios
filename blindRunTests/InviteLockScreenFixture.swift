import CoreLocation
import XCTest
@testable import blindRun

/// `InviteLockScreenActionTests` 与 `InviteLockScreenLandingTests` 共用的夹具（#338）。
@MainActor
enum InviteLockScreenFixture {

    /// 锁屏那条通知对应的操作：身份取自同一张邀请（`NEW_ORDER` 的 APNs 没有 `inviteId`，只有单号与期限）。
    static func lockScreen(_ action: InviteNotificationActions.Action, for dispatch: WSNewOrder) -> InviteNotificationActions.Request {
        .init(action: action, invite: InviteIdentity(orderId: dispatch.orderId, inviteId: nil, expiresAt: dispatch.expiresAt?.backendTimestamp))
    }

    static func dispatch(
        orderId: Int64, inviteId: Int64, expiresIn seconds: TimeInterval = 900, requiresIntroCall: Bool = false
    ) -> WSNewOrder {
        var order = OrderDetailResponse.previewDispatch(orderId: orderId, requiresIntroCall: requiresIntroCall)
        order.inviteId = inviteId
        order.expiresAt = DateFormatter.aidRunBackendLocalDateTime.string(from: Date().addingTimeInterval(seconds))
        return order
    }

    /// 返回 `AppState` 让调用方攥着：view model 对它是 `weak`。
    static func makeHome(
        declineStreak: VolunteerDeclineStreak? = nil
    ) -> (VolunteerHomeViewModel, AppState, WebSocketService, SpeechService) {
        let appState = AppState()
        let service = WebSocketService()
        appState.realtimeCoordinator.attach(to: service, role: .volunteer)
        let speech = SpeechService()
        let viewModel = declineStreak.map { VolunteerHomeViewModel(declineStreak: $0) } ?? VolunteerHomeViewModel()
        viewModel.configure(with: appState, speechService: speech)
        viewModel.isDispatchHubVisible = true
        return (viewModel, appState, service, speech)
    }

    /// 走真实回复路径用：订单服务是替身，资料已审核通过、定位已授权（`respondToDispatch` 的闸要放行）。
    static func makeVolunteerHome(
        orders: FakeOrderService, declineStreak: VolunteerDeclineStreak? = nil
    ) -> (VolunteerHomeViewModel, AppState) {
        let appState = AppState(orders: orders)
        appState.currentEnvironment = .mock
        appState.userId = 42
        appState.updateVolunteerProfile(VolunteerProfileResponse(
            name: "测试志愿者", verificationStatus: "approved", adminReviewStatus: nil, registrationStep: nil,
            canAcceptOrders: nil, isAvailable: true, availableTimeSlots: nil, acceptsGuideDog: nil, paceRange: nil
        ))
        appState.realtimeCoordinator.attach(to: WebSocketService(), role: .volunteer)
        let viewModel = declineStreak.map { VolunteerHomeViewModel(declineStreak: $0) } ?? VolunteerHomeViewModel()
        viewModel.configure(
            with: appState, speechService: SpeechService(),
            currentLocationProvider: { CLLocationCoordinate2D(latitude: 22.52, longitude: 113.93) },
            locationAuthorizedProvider: { true }
        )
        return (viewModel, appState)
    }

    static func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}
