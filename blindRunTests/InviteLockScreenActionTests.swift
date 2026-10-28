import CoreLocation
import UserNotifications
import XCTest
@testable import blindRun

/// 邀请类 APNs 的锁屏操作与连续拒绝的后端计数（#338，后端 #369 #370 / SPEC D11）。
///
/// 本机只有免费个人团队，拿不到推送 token（#201），真实推送到不了这台手机。这里守的是推送到了之后
/// 每一步做得对不对：category 注册、操作落到卡片上同一条路径、只回复身份对得上的那张、旧通知按邀请收掉、
/// 前台 WS 与 APNs 只出现一次、冷启动不丢。409 的说明由卡片那条路径负责（`InviteModelTests`）。
@MainActor
final class InviteLockScreenActionTests: XCTestCase {

    // MARK: - category 注册（契约「邀请类 APNs」）

    func testCategoriesMatchTheContract() throws {
        let categories = Dictionary(
            uniqueKeysWithValues: InviteNotificationActions.categories.map { ($0.identifier, $0) }
        )
        let invite = try XCTUnwrap(categories["INVITE"])
        XCTAssertEqual(invite.actions.map(\.identifier), ["ACCEPT_INVITE", "DECLINE_INVITE"])
        let accept = invite.actions[0], decline = invite.actions[1]
        XCTAssertTrue(accept.options.contains(.authenticationRequired), "接下要解锁（后端 #369）")
        XCTAssertTrue(decline.options.contains(.authenticationRequired))
        XCTAssertTrue(decline.options.contains(.destructive))
        // 两个都拉起 App：后台拉起时根视图未必加载、会话未必恢复，回复会静默丢失（安全复核 HIGH 2）。
        XCTAssertTrue(accept.options.contains(.foreground))
        XCTAssertTrue(decline.options.contains(.foreground))

        let introCall = try XCTUnwrap(categories["INVITE_INTRO_CALL"])
        XCTAssertEqual(introCall.actions.map(\.identifier), ["DECLINE_INVITE"], "要先通话的单锁屏上不给「接下」")
    }

    // MARK: - 操作解析

    func testRequestParsesTheContractKeys() throws {
        let userInfo: [AnyHashable: Any] = [
            "eventType": "INVITE_EXPIRING", "orderId": NSNumber(value: 7), "inviteId": NSNumber(value: 901),
            "expiresAt": "2026-10-06T10:30:00",
        ]
        let request = try XCTUnwrap(InviteNotificationActions.request(actionIdentifier: "DECLINE_INVITE", userInfo: userInfo))
        XCTAssertEqual(request.action, .decline)
        XCTAssertEqual(request.invite, InviteIdentity(orderId: 7, inviteId: 901, expiresAt: "2026-10-06T10:30:00".backendTimestamp))

        XCTAssertEqual(
            InviteNotificationActions.request(actionIdentifier: "ACCEPT_INVITE", userInfo: ["orderId": "8"])?.invite.orderId, 8,
            "字符串单号也认，免得换一次序列化就整条操作静默失效"
        )
        XCTAssertNil(
            InviteNotificationActions.request(actionIdentifier: UNNotificationDefaultActionIdentifier, userInfo: userInfo),
            "点通知本身不是邀请操作"
        )
        for bad in [[:], ["orderId": NSNumber(value: true)], ["orderId": NSNumber(value: 1.9)], ["orderId": NSNumber(value: 0)],
                    ["orderId": "-5"], ["orderId": "+5"]] as [[AnyHashable: Any]] {
            XCTAssertNil(InviteNotificationActions.request(actionIdentifier: "ACCEPT_INVITE", userInfo: bad), "\(bad) 不是合法单号")
        }
    }

    /// 前台的 `NEW_ORDER`：系统什么都不出，改去对一次待回复列表（复核 A：接线要有用例）。
    func testForegroundNewInviteShowsNothingAndReconciles() async {
        XCTAssertEqual(InviteNotificationActions.foregroundPresentationOptions(for: ["eventType": "NEW_ORDER"]), [])
        XCTAssertEqual(InviteNotificationActions.foregroundPresentationOptions(for: ["eventType": "INVITE_EXPIRING"]), [.banner, .sound])
        XCTAssertEqual(InviteNotificationActions.foregroundPresentationOptions(for: ["eventType": "EMERGENCY_TRIGGERED"]), [.banner, .sound])

        let orders = FakeOrderService()
        orders.pendingInvitesResult = .success(PendingInvitesResponse(consecutiveDeclineCount: 0, invites: []))
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        defer { persistence.reset() }
        let appState = AppState(orders: orders, persistence: persistence, tokenStore: InMemoryTokenStore())
        appState.accessToken = "token"
        appState.userId = 42
        appState.activeRole = .volunteer
        let manager = PushNotificationsManager()
        manager.configure(appState: appState, speechService: SpeechService())

        await manager.absorbForegroundInvite()

        XCTAssertEqual(orders.callCount("pendingInvites()"), 1)
    }

    /// 前台只吞 `NEW_ORDER`（WS 也会到）；`INVITE_EXPIRING` 照旧弹出 —— App 不处理 WS 那一条，吞掉就什么提醒都没有。
    func testOnlyNewInvitesAreSwallowedInTheForeground() {
        XCTAssertTrue(InviteNotificationActions.isForegroundDuplicate(["eventType": "NEW_ORDER"]))
        XCTAssertFalse(InviteNotificationActions.isForegroundDuplicate(["eventType": "INVITE_EXPIRING"]))
        XCTAssertFalse(InviteNotificationActions.isForegroundDuplicate(["eventType": "EMERGENCY_TRIGGERED"]))
        XCTAssertTrue(InviteNotificationActions.isInviteEvent(["eventType": "INVITE_EXPIRING"]))
        XCTAssertFalse(InviteNotificationActions.isInviteEvent([:]))
    }

    // MARK: - 已送达的旧通知

    /// 按邀请身份收：同一单撤回后的新邀请（期限不同）那条通知要留着（安全复核 MEDIUM 4）。
    func testPruneRemovesOnlyTheNamedInviteOrThoseMissingFromAnEarlierSnapshot() {
        let requestedAt = Date()
        let old = requestedAt.addingTimeInterval(300), new = requestedAt.addingTimeInterval(900)
        let delivered = [
            DeliveredInviteNotification(identifier: "a", invite: InviteIdentity(orderId: 7, inviteId: nil, expiresAt: old), date: requestedAt.addingTimeInterval(-60)),
            DeliveredInviteNotification(identifier: "b", invite: InviteIdentity(orderId: 7, inviteId: nil, expiresAt: new), date: requestedAt.addingTimeInterval(-30)),
            DeliveredInviteNotification(identifier: "c", invite: InviteIdentity(orderId: 8, inviteId: nil, expiresAt: old), date: requestedAt.addingTimeInterval(-60)),
            DeliveredInviteNotification(identifier: "d", invite: InviteIdentity(orderId: 9, inviteId: nil, expiresAt: old), date: requestedAt.addingTimeInterval(5)),
        ]
        XCTAssertEqual(
            InviteNotificationActions.identifiersToRemove(delivered, .invites([InviteIdentity(orderId: 7, inviteId: nil, expiresAt: old)])), ["a"]
        )
        XCTAssertEqual(
            InviteNotificationActions.identifiersToRemove(delivered, .allExcept([7], deliveredBefore: requestedAt)), ["c"],
            "9 号是请求在路上时到的，不在快照里也不能收"
        )
        XCTAssertNil(
            InviteNotificationActions.deliveredInvite(identifier: "x", date: requestedAt, userInfo: ["eventType": "EMERGENCY_TRIGGERED", "orderId": 7]),
            "求助类通知不归这里收"
        )
    }

    /// 撤回只收**队列里那一张**的通知（带它的期限）；队列里没有的撤回不收 —— 不知道期限，按单号收会把同单新邀请那条一起收掉，
    /// 留给下一次对账（`withdrawDispatch` 的注释）。回复（`clearDispatch`）收这一单的全部；对账收快照里没有的。
    func testCoordinatorPrunesOnWithdrawReplyAndReconcile() async {
        let (viewModel, appState, service, _) = InviteLockScreenFixture.makeHome()
        let coordinator = appState.realtimeCoordinator
        var prunes: [InviteNotificationPrune] = []
        coordinator.pruneDeliveredInviteNotifications = { prunes.append($0) }
        service.simulateIncomingEventForTesting(.newOrder(InviteLockScreenFixture.dispatch(orderId: 7, inviteId: 71)))
        await InviteLockScreenFixture.waitUntil { coordinator.pendingDispatches.contains { $0.order.orderId == 7 } }
        let queuedExpiry = coordinator.pendingDispatches.first { $0.order.orderId == 7 }?.expiresAt
        XCTAssertNotNil(queuedExpiry, "前提：单 7 进了队列、带期限")

        service.simulateIncomingEventForTesting(.inviteWithdrawn(WSInviteWithdrawn(orderId: 10, inviteId: 101, reason: "TAKEN")))
        service.simulateIncomingEventForTesting(.inviteWithdrawn(WSInviteWithdrawn(orderId: 7, inviteId: 71, reason: "TAKEN")))
        await InviteLockScreenFixture.waitUntil { !prunes.isEmpty }
        coordinator.clearDispatch(orderID: 8)
        let requestedAt = Date()
        coordinator.reconcilePendingInvites([InviteLockScreenFixture.dispatch(orderId: 9, inviteId: 91)], requestedAt: requestedAt)

        XCTAssertEqual(prunes, [
            .invites([InviteIdentity(orderId: 7, inviteId: 71, expiresAt: queuedExpiry)]),
            .invites([InviteIdentity(orderId: 8, inviteId: nil, expiresAt: nil)]),
            .allExcept([9], deliveredBefore: requestedAt),
        ], "单 10 不在队列里，它的撤回不该收任何通知")
        withExtendedLifetime(viewModel) {}
    }

    // MARK: - 连续拒绝：后端计数（SPEC D11）

    func testDeclineStreakFollowsTheBackendCountAndAsksAgainOnlyAfterThreeMore() throws {
        let suite = "\(#function)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let streak = VolunteerDeclineStreak(defaults: defaults)

        streak.adoptServerCount(2)
        XCTAssertFalse(streak.shouldAskAboutAvailability)
        streak.adoptServerCount(3)
        XCTAssertTrue(streak.shouldAskAboutAvailability, "后端数到 3（含过期）就问")

        streak.acknowledgeAsked()
        streak.adoptServerCount(5)
        XCTAssertFalse(streak.shouldAskAboutAvailability, "问过一次，涨到 5 还不该再问")
        streak.adoptServerCount(6)
        XCTAssertTrue(streak.shouldAskAboutAvailability, "比上次问时再涨 3 才再问")

        streak.acknowledgeAsked()
        streak.adoptServerCount(0)
        streak.adoptServerCount(3)
        XCTAssertTrue(streak.shouldAskAboutAvailability, "后端清零（接了单）之后从头算")
    }

    /// 快照带回来的次数要真的进到首页的判断里。
    func testSnapshotCountReachesTheHomePrompt() async throws {
        let suite = "\(#function)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let (viewModel, appState, _, _) = InviteLockScreenFixture.makeHome(declineStreak: VolunteerDeclineStreak(defaults: defaults))

        appState.realtimeCoordinator.reconcilePendingInvites([], requestedAt: Date(), consecutiveDeclineCount: 3)
        await InviteLockScreenFixture.waitUntil { viewModel.shouldAskAboutAvailability }

        XCTAssertTrue(viewModel.shouldAskAboutAvailability)
    }
}
