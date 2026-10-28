import CoreLocation
import XCTest
@testable import blindRun

/// 锁屏邀请操作落地（#338）：App 被拉起后，首页按邀请身份认领那一张，走卡片上同一条路径。
/// 从 `InviteLockScreenActionTests` 拆出（SwiftLint 上限）。夹具在 `InviteLockScreenFixture`。
@MainActor
final class InviteLockScreenLandingTests: XCTestCase {

    // MARK: - 锁屏操作落地

    /// 「接下」：翻到那一张、弹出卡片，走卡片上同一个 `respondToDispatch`（定位闸、改发、409 都在那条路上）。
    func testLockScreenAcceptGoesThroughTheCardsRespondToDispatch() async {
        let orders = FakeOrderService()
        orders.respondResult = .success(())
        let (viewModel, appState) = InviteLockScreenFixture.makeVolunteerHome(orders: orders)
        let coordinator = appState.realtimeCoordinator
        let target = InviteLockScreenFixture.dispatch(orderId: 22, inviteId: 221)
        coordinator.reconcilePendingInvites([InviteLockScreenFixture.dispatch(orderId: 21, inviteId: 211), target], requestedAt: Date())
        await InviteLockScreenFixture.waitUntil { viewModel.invites.count == 2 }

        coordinator.requestLockScreenInviteAction(InviteLockScreenFixture.lockScreen(.accept, for: target), userID: appState.userId)
        await InviteLockScreenFixture.waitUntil { orders.lastRespondAction != nil }

        XCTAssertEqual(orders.lastOrderId, 22, "要回复锁屏上那一张，不是队首")
        XCTAssertEqual(orders.lastRespondAction, .accept)
        XCTAssertEqual(viewModel.currentInviteID, 22)
        XCTAssertNil(coordinator.lockScreenInviteAction, "接手之后要清掉，免得下一次对账再触发一次")
    }

    /// 「这次去不了」：走卡片上同一个 `declineInvite`（进 5 秒撤销窗口、有回执），不在后台直接发。
    func testLockScreenDeclineUsesTheSameUndoableDecline() async {
        let (viewModel, appState, _, speech) = InviteLockScreenFixture.makeHome()
        let coordinator = appState.realtimeCoordinator
        let target = InviteLockScreenFixture.dispatch(orderId: 23, inviteId: 231)
        coordinator.reconcilePendingInvites([target], requestedAt: Date())
        await InviteLockScreenFixture.waitUntil { viewModel.invites.count == 1 }

        coordinator.requestLockScreenInviteAction(InviteLockScreenFixture.lockScreen(.decline, for: target))
        await InviteLockScreenFixture.waitUntil { viewModel.pendingDecline != nil }

        XCTAssertEqual(viewModel.pendingDecline?.id, 23)
        XCTAssertTrue(viewModel.invites.isEmpty)
        XCTAssertTrue(speech.lastSpokenText?.hasPrefix(VolunteerInviteCopy.declineToastText) == true)
    }

    /// 锁屏那条是旧邀请（期限不同），队列里是同一单撤回后的新邀请：不许替他回复新的那张（安全复核 MEDIUM 6 / 7）。
    func testLockScreenActionIgnoresANewerInviteForTheSameOrder() async {
        let (viewModel, appState, _, _) = InviteLockScreenFixture.makeHome()
        let coordinator = appState.realtimeCoordinator
        coordinator.reconcilePendingInvites([InviteLockScreenFixture.dispatch(orderId: 41, inviteId: 412, expiresIn: 900)], requestedAt: Date())
        await InviteLockScreenFixture.waitUntil { viewModel.invites.count == 1 }

        let oldNotification = InviteIdentity(orderId: 41, inviteId: nil, expiresAt: Date().addingTimeInterval(300))
        coordinator.requestLockScreenInviteAction(.init(action: .decline, invite: oldNotification))
        try? await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertNil(viewModel.pendingDecline, "替他回复了同单的新邀请")
        XCTAssertNotNil(coordinator.lockScreenInviteAction, "还没等到对账，先留着")
    }

    /// 两边都有 `inviteId` 时只认它：分批派单里同一单的几张邀请可能同一个截止时刻。
    func testInviteIdentityPrefersTheInviteIdOverTheDeadline() {
        let deadline = Date()
        let identity = InviteIdentity(orderId: 7, inviteId: 71, expiresAt: deadline)
        XCTAssertFalse(identity.matches(orderId: 7, inviteId: 72, expiresAt: deadline), "同单同期限、不同 inviteId 是两张")
        XCTAssertTrue(identity.matches(orderId: 7, inviteId: 71, expiresAt: deadline.addingTimeInterval(30)), "inviteId 相同就是同一张")
        XCTAssertFalse(identity.matches(orderId: 8, inviteId: 71, expiresAt: deadline), "单号不同")
    }

    /// 按下之后的那次对账里没有它 ⇒ 已失效，告诉他。他按了，不能没有回应。
    func testLockScreenActionForAGoneInviteSaysItIsInvalid() async {
        // view model 必须攥住：它对锁屏操作的订阅是 `[weak self]`，丢掉它就没人处理，断言什么都验不到（10-28 真机红）。
        let (viewModel, appState, _, speech) = InviteLockScreenFixture.makeHome()
        let coordinator = appState.realtimeCoordinator
        coordinator.requestLockScreenInviteAction(.init(
            action: .accept, invite: InviteIdentity(orderId: 31, inviteId: nil, expiresAt: Date().addingTimeInterval(600))
        ))

        coordinator.reconcilePendingInvites([], requestedAt: Date())
        await InviteLockScreenFixture.waitUntil { coordinator.lockScreenInviteAction == nil }

        XCTAssertEqual(speech.lastSpokenText, "这个邀请已失效，不需要再回复了")
        withExtendedLifetime(viewModel) {}
    }

    /// 按下**之前**发出、之后才回来的旧快照里没有它，不能据此判失效：那张可能还在（复核 A：时间闸）。
    func testAnOlderSnapshotDoesNotInvalidateTheLockScreenAction() async {
        // view model 必须攥住：它对锁屏操作的订阅是 `[weak self]`，丢掉它就没人处理，断言什么都验不到（10-28 真机红）。
        let (viewModel, appState, _, speech) = InviteLockScreenFixture.makeHome()
        let coordinator = appState.realtimeCoordinator
        coordinator.requestLockScreenInviteAction(.init(
            action: .accept, invite: InviteIdentity(orderId: 33, inviteId: nil, expiresAt: Date().addingTimeInterval(600))
        ))

        coordinator.reconcilePendingInvites([], requestedAt: Date().addingTimeInterval(-60))
        try? await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertNotNil(coordinator.lockScreenInviteAction)
        XCTAssertNotEqual(speech.lastSpokenText, "这个邀请已失效，不需要再回复了")

        // 对照：按下之后的快照里没有它才判失效 —— 证明上面不是因为没人处理才「没判」。
        coordinator.reconcilePendingInvites([], requestedAt: Date())
        await InviteLockScreenFixture.waitUntil { coordinator.lockScreenInviteAction == nil }
        XCTAssertEqual(speech.lastSpokenText, "这个邀请已失效，不需要再回复了")
        withExtendedLifetime(viewModel) {}
    }

    /// 邀请期限已过：不等对账，直接告诉他。
    func testLockScreenActionForAnExpiredInviteSaysItIsInvalid() async {
        // view model 必须攥住：它对锁屏操作的订阅是 `[weak self]`，丢掉它就没人处理，断言什么都验不到（10-28 真机红）。
        let (viewModel, appState, _, speech) = InviteLockScreenFixture.makeHome()
        let coordinator = appState.realtimeCoordinator
        coordinator.requestLockScreenInviteAction(.init(
            action: .decline, invite: InviteIdentity(orderId: 32, inviteId: nil, expiresAt: Date().addingTimeInterval(-1))
        ))
        await InviteLockScreenFixture.waitUntil { coordinator.lockScreenInviteAction == nil }

        XCTAssertEqual(speech.lastSpokenText, "这个邀请已失效，不需要再回复了")
        withExtendedLifetime(viewModel) {}
    }

    /// 按下时是另一个账号（同一台手机换了人登录）：丢掉，不替这个账号回复（复核 B）。
    func testLockScreenActionFromAnotherAccountIsDropped() async {
        let (viewModel, appState, _, _) = InviteLockScreenFixture.makeHome()
        appState.userId = 42
        let coordinator = appState.realtimeCoordinator
        let target = InviteLockScreenFixture.dispatch(orderId: 34, inviteId: 341)
        coordinator.reconcilePendingInvites([target], requestedAt: Date())
        await InviteLockScreenFixture.waitUntil { viewModel.invites.count == 1 }

        coordinator.requestLockScreenInviteAction(InviteLockScreenFixture.lockScreen(.decline, for: target), userID: 999)
        await InviteLockScreenFixture.waitUntil { coordinator.lockScreenInviteAction == nil }

        XCTAssertNil(viewModel.pendingDecline, "替另一个账号回复了")
        XCTAssertEqual(viewModel.invites.count, 1)
    }

    /// 冷启动：按下时首页还没建、WS 接上那一刻协调器会走一次会话清理。意图不能被那次清理抹掉（安全复核 HIGH 1）。
    func testLockScreenActionSurvivesTheColdStartSessionReset() async {
        let appState = AppState()
        let coordinator = appState.realtimeCoordinator
        let target = InviteLockScreenFixture.dispatch(orderId: 51, inviteId: 511)
        coordinator.requestLockScreenInviteAction(InviteLockScreenFixture.lockScreen(.decline, for: target))

        coordinator.attach(to: WebSocketService(), role: .volunteer)  // 冷启动接 WS：detach(clearSessionState: true)
        XCTAssertNotNil(coordinator.lockScreenInviteAction)

        let viewModel = VolunteerHomeViewModel()
        viewModel.configure(with: appState, speechService: SpeechService())
        coordinator.reconcilePendingInvites([target], requestedAt: Date())
        await InviteLockScreenFixture.waitUntil { viewModel.pendingDecline != nil }
        XCTAssertEqual(viewModel.pendingDecline?.id, 51)
    }

    /// 冷启动：系统在 `configure` 之前就回调了 delegate。那一下要存着，配好之后交给协调器。
    func testActionArrivingBeforeConfigureIsKept() {
        let manager = PushNotificationsManager()
        let request = InviteNotificationActions.Request(action: .accept, invite: InviteIdentity(orderId: 61, inviteId: nil, expiresAt: nil))
        manager.handleInviteAction(request)

        let appState = AppState()
        manager.configure(appState: appState, speechService: SpeechService())

        XCTAssertEqual(appState.realtimeCoordinator.lockScreenInviteAction, request)
    }

    /// 「有意向」与接单一样清零连续拒绝（后端口径），不等下一次快照（复核 A）。
    func testInterestedClearsTheDeclineStreak() async throws {
        let suite = "\(#function)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let streak = VolunteerDeclineStreak(defaults: defaults)
        streak.adoptServerCount(3)
        let orders = FakeOrderService()
        orders.respondResult = .success(())
        let (viewModel, appState) = InviteLockScreenFixture.makeVolunteerHome(orders: orders, declineStreak: streak)
        appState.realtimeCoordinator.reconcilePendingInvites([InviteLockScreenFixture.dispatch(orderId: 24, inviteId: 241, requiresIntroCall: true)], requestedAt: Date())
        await InviteLockScreenFixture.waitUntil { viewModel.invites.count == 1 }
        XCTAssertTrue(viewModel.shouldAskAboutAvailability)

        viewModel.respondToDispatch(action: .interested, currentLocation: nil, locationAuthorized: false, orderId: 24)
        await InviteLockScreenFixture.waitUntil { orders.lastRespondAction != nil }
        await InviteLockScreenFixture.waitUntil { !viewModel.shouldAskAboutAvailability }

        XCTAssertEqual(orders.lastRespondAction, .interested)
        XCTAssertFalse(viewModel.shouldAskAboutAvailability, "有意向之后还在问「要不要调整空闲时间」")
    }
}
