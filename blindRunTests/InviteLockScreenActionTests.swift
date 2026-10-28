import UserNotifications
import XCTest
@testable import blindRun

/// 邀请类 APNs 的锁屏操作与连续拒绝的后端计数（#338，后端 #369 #370 / SPEC D11）。
///
/// 本机只有免费个人团队，拿不到推送 token（#201），真实推送到不了这台手机。这里守的是推送到了之后
/// 每一步做得对不对：category 注册、操作调对接口、409 说对原因、旧通知按单号收掉、WS 与 APNs 只出现一次。
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
        XCTAssertTrue(accept.options.contains(.foreground), "接下要拉起 App，走卡片上同一条接单路径")
        XCTAssertTrue(decline.options.contains(.authenticationRequired))
        XCTAssertTrue(decline.options.contains(.destructive))

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
        XCTAssertEqual(request.orderId, 7)
        XCTAssertEqual(request.inviteId, 901)
        XCTAssertEqual(request.expiresAt, "2026-10-06T10:30:00".backendTimestamp)

        XCTAssertEqual(
            InviteNotificationActions.request(actionIdentifier: "ACCEPT_INVITE", userInfo: ["orderId": "8"])?.orderId, 8,
            "字符串单号也认，免得换一次序列化就整条操作静默失效"
        )
        XCTAssertNil(
            InviteNotificationActions.request(actionIdentifier: UNNotificationDefaultActionIdentifier, userInfo: userInfo),
            "点通知本身不是邀请操作"
        )
        XCTAssertNil(InviteNotificationActions.request(actionIdentifier: "ACCEPT_INVITE", userInfo: [:]), "缺单号不能回复")
    }

    func testOnlyInviteEventsAreInvites() {
        XCTAssertTrue(InviteNotificationActions.isInviteEvent(["eventType": "NEW_ORDER"]))
        XCTAssertTrue(InviteNotificationActions.isInviteEvent(["eventType": "INVITE_EXPIRING"]))
        XCTAssertFalse(InviteNotificationActions.isInviteEvent(["eventType": "EMERGENCY_TRIGGERED"]))
        XCTAssertFalse(InviteNotificationActions.isInviteEvent([:]))
    }

    // MARK: - 锁屏「这次去不了」

    func testDeclineFromTheLockScreenRespondsAndRetiresTheInvite() async {
        let (appState, orders, persistence) = makeSession()
        defer { persistence.reset() }
        orders.respondResult = .success(())
        let request = InviteNotificationActions.Request(action: .decline, orderId: 7, inviteId: nil, expiresAt: Date().addingTimeInterval(600))

        let failure = await appState.declineInviteFromNotification(request)

        XCTAssertNil(failure)
        XCTAssertEqual(orders.lastRespondAction, .decline)
        // 回前台那次对账还带着它（后端还没处理完），不能把它当新邀请灌回来。
        appState.realtimeCoordinator.reconcilePendingInvites([Self.dispatch(orderId: 7, inviteId: 71)], requestedAt: Date())
        XCTAssertTrue(appState.realtimeCoordinator.pendingDispatches.isEmpty)
    }

    /// 409 两种原因各说各的（契约：给对应说明，不给通用报错）；其余错误让他打开 App 再试。
    func testDeclineFailureSaysWhy() async {
        let cases: [(String, String, String)] = [
            ("ORDER_ALREADY_ACCEPTED", "这个邀请已失效", "已有其他陪跑员接下"),
            ("ORDER_DISPATCH_MISMATCH", "这个邀请已失效", "回复时间已过"),
            ("INTERNAL_ERROR", "没能回复这个邀请", "请打开 App 再试一次"),
        ]
        for (code, title, body) in cases {
            let (appState, orders, persistence) = makeSession()
            orders.respondResult = .failure(APIError.serverError(ErrorResponse(code: code, message: "后端原文")))
            let request = InviteNotificationActions.Request(action: .decline, orderId: 7, inviteId: nil, expiresAt: nil)

            let failure = await appState.declineInviteFromNotification(request)

            XCTAssertEqual(failure?.title, title, code)
            XCTAssertEqual(failure?.body, body, code)
            persistence.reset()
        }
    }

    // MARK: - 已送达的旧通知

    func testPruneRemovesOnlyTheNamedOrdersOrThoseMissingFromAnEarlierSnapshot() {
        let requestedAt = Date()
        let delivered = [
            DeliveredInviteNotification(identifier: "a", orderId: 7, date: requestedAt.addingTimeInterval(-60)),
            DeliveredInviteNotification(identifier: "b", orderId: 8, date: requestedAt.addingTimeInterval(-60)),
            DeliveredInviteNotification(identifier: "c", orderId: 9, date: requestedAt.addingTimeInterval(5)),
        ]
        XCTAssertEqual(InviteNotificationActions.identifiersToRemove(delivered, .orders([7])), ["a"])
        XCTAssertEqual(
            InviteNotificationActions.identifiersToRemove(delivered, .allExcept([8], deliveredBefore: requestedAt)), ["a"],
            "9 号是请求在路上时到的，不在快照里也不能收"
        )
        XCTAssertNil(
            InviteNotificationActions.deliveredInvite(identifier: "x", date: requestedAt, userInfo: ["eventType": "EMERGENCY_TRIGGERED", "orderId": 7]),
            "求助类通知不归这里收"
        )
    }

    func testCoordinatorPrunesOnWithdrawReplyAndReconcile() async {
        let (viewModel, appState, service, _) = makeHome()
        _ = viewModel
        var prunes: [InviteNotificationPrune] = []
        appState.realtimeCoordinator.pruneDeliveredInviteNotifications = { prunes.append($0) }

        service.simulateIncomingEventForTesting(.inviteWithdrawn(WSInviteWithdrawn(orderId: 7, inviteId: 71, reason: "TAKEN")))
        await waitUntil { !prunes.isEmpty }
        appState.realtimeCoordinator.clearDispatch(orderID: 8)
        let requestedAt = Date()
        appState.realtimeCoordinator.reconcilePendingInvites([Self.dispatch(orderId: 9, inviteId: 91)], requestedAt: requestedAt)

        XCTAssertEqual(prunes, [.orders([7]), .orders([8]), .allExcept([9], deliveredBefore: requestedAt)])
    }

    // MARK: - 锁屏「接下」

    /// 这张邀请在队列里 ⇒ 翻到它、弹出卡片，交给宿主走卡片上同一个 `respondToDispatch`。
    func testLockScreenAcceptOpensTheInviteAndHandsTheSameAcceptToTheHost() async {
        let (viewModel, appState, _, _) = makeHome()
        let coordinator = appState.realtimeCoordinator
        coordinator.reconcilePendingInvites(
            [Self.dispatch(orderId: 21, inviteId: 211), Self.dispatch(orderId: 22, inviteId: 221)], requestedAt: Date()
        )
        await waitUntil { viewModel.invites.count == 2 }

        coordinator.requestLockScreenAccept(orderID: 22, inviteID: nil)
        await waitUntil { viewModel.lockScreenAcceptRequest != nil }

        XCTAssertEqual(viewModel.lockScreenAcceptRequest, VolunteerLockScreenAcceptRequest(orderId: 22, action: .accept))
        XCTAssertEqual(viewModel.currentInviteID, 22, "要翻到锁屏上那一张，不是队首")
        XCTAssertTrue(viewModel.isInviteSheetPresented)
        XCTAssertNil(coordinator.lockScreenAccept, "接手之后要清掉，免得下一次对账再触发一次接单")
    }

    /// 按下之后的那次对账里没有它 ⇒ 已失效，告诉他。他按了「接下」，不能没有回应。
    func testLockScreenAcceptForAGoneInviteSaysItIsInvalid() async {
        let (viewModel, appState, _, speech) = makeHome()
        let coordinator = appState.realtimeCoordinator
        coordinator.requestLockScreenAccept(orderID: 31, inviteID: nil)

        coordinator.reconcilePendingInvites([], requestedAt: Date())
        await waitUntil { coordinator.lockScreenAccept == nil }

        XCTAssertNil(viewModel.lockScreenAcceptRequest)
        XCTAssertEqual(speech.lastSpokenText, "这个邀请已失效，不需要再回复了")
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
        let (viewModel, appState, _, _) = makeHome(declineStreak: VolunteerDeclineStreak(defaults: defaults))

        appState.realtimeCoordinator.reconcilePendingInvites([], requestedAt: Date(), consecutiveDeclineCount: 3)
        await waitUntil { viewModel.shouldAskAboutAvailability }

        XCTAssertTrue(viewModel.shouldAskAboutAvailability)
    }

    // MARK: - Fixture

    private static func dispatch(orderId: Int64, inviteId: Int64, expiresIn seconds: TimeInterval = 900) -> WSNewOrder {
        var order = OrderDetailResponse.previewDispatch(orderId: orderId, requiresIntroCall: false)
        order.inviteId = inviteId
        order.expiresAt = DateFormatter.aidRunBackendLocalDateTime.string(from: Date().addingTimeInterval(seconds))
        return order
    }

    /// 返回 `AppState` 让调用方攥着：view model 对它是 `weak`。
    private func makeHome(
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

    private func makeSession() -> (AppState, FakeOrderService, UserDefaultsAppStatePersistence) {
        let orders = FakeOrderService()
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        // 内存 token 库：`accessToken` 的 didSet 会落库，用真 Keychain 会污染设备。
        let appState = AppState(orders: orders, persistence: persistence, tokenStore: InMemoryTokenStore())
        appState.accessToken = "token"
        appState.userId = 42
        appState.activeRole = .volunteer
        return (appState, orders, persistence)
    }

    private func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}
