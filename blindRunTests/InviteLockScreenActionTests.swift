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

        XCTAssertEqual(prunes, [
            .invites([InviteIdentity(orderId: 7, inviteId: 71, expiresAt: nil)]),
            .invites([InviteIdentity(orderId: 8, inviteId: nil, expiresAt: nil)]),
            .allExcept([9], deliveredBefore: requestedAt),
        ])
    }

    // MARK: - 锁屏操作落地

    /// 「接下」：翻到那一张、弹出卡片，交给宿主走卡片上同一个 `respondToDispatch`。
    func testLockScreenAcceptOpensTheInviteAndHandsTheSameAcceptToTheHost() async {
        let (viewModel, appState, _, _) = makeHome()
        let coordinator = appState.realtimeCoordinator
        let target = Self.dispatch(orderId: 22, inviteId: 221)
        coordinator.reconcilePendingInvites([Self.dispatch(orderId: 21, inviteId: 211), target], requestedAt: Date())
        await waitUntil { viewModel.invites.count == 2 }

        coordinator.requestLockScreenInviteAction(Self.lockScreen(.accept, for: target))
        await waitUntil { viewModel.lockScreenAcceptRequest != nil }

        XCTAssertEqual(viewModel.lockScreenAcceptRequest, VolunteerLockScreenAcceptRequest(orderId: 22, action: .accept))
        XCTAssertEqual(viewModel.currentInviteID, 22, "要翻到锁屏上那一张，不是队首")
        XCTAssertTrue(viewModel.isInviteSheetPresented)
        XCTAssertNil(coordinator.lockScreenInviteAction, "接手之后要清掉，免得下一次对账再触发一次")
    }

    /// 「这次去不了」：走卡片上同一个 `declineInvite`（进 5 秒撤销窗口、有回执），不在后台直接发。
    func testLockScreenDeclineUsesTheSameUndoableDecline() async {
        let (viewModel, appState, _, speech) = makeHome()
        let coordinator = appState.realtimeCoordinator
        let target = Self.dispatch(orderId: 23, inviteId: 231)
        coordinator.reconcilePendingInvites([target], requestedAt: Date())
        await waitUntil { viewModel.invites.count == 1 }

        coordinator.requestLockScreenInviteAction(Self.lockScreen(.decline, for: target))
        await waitUntil { viewModel.pendingDecline != nil }

        XCTAssertEqual(viewModel.pendingDecline?.id, 23)
        XCTAssertTrue(viewModel.invites.isEmpty)
        XCTAssertTrue(speech.lastSpokenText?.hasPrefix(VolunteerInviteCopy.declineToastText) == true)
    }

    /// 锁屏那条是旧邀请（期限不同），队列里是同一单撤回后的新邀请：不许替他回复新的那张（安全复核 MEDIUM 6 / 7）。
    func testLockScreenActionIgnoresANewerInviteForTheSameOrder() async {
        let (viewModel, appState, _, _) = makeHome()
        let coordinator = appState.realtimeCoordinator
        coordinator.reconcilePendingInvites([Self.dispatch(orderId: 41, inviteId: 412, expiresIn: 900)], requestedAt: Date())
        await waitUntil { viewModel.invites.count == 1 }

        let oldNotification = InviteIdentity(orderId: 41, inviteId: nil, expiresAt: Date().addingTimeInterval(300))
        coordinator.requestLockScreenInviteAction(.init(action: .accept, invite: oldNotification))
        try? await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertNil(viewModel.lockScreenAcceptRequest)
        XCTAssertNotNil(coordinator.lockScreenInviteAction, "还没等到对账，先留着")
    }

    /// 按下之后的那次对账里没有它 ⇒ 已失效，告诉他。他按了，不能没有回应。
    func testLockScreenActionForAGoneInviteSaysItIsInvalid() async {
        let (viewModel, appState, _, speech) = makeHome()
        let coordinator = appState.realtimeCoordinator
        coordinator.requestLockScreenInviteAction(.init(
            action: .accept, invite: InviteIdentity(orderId: 31, inviteId: nil, expiresAt: Date().addingTimeInterval(600))
        ))

        coordinator.reconcilePendingInvites([], requestedAt: Date())
        await waitUntil { coordinator.lockScreenInviteAction == nil }

        XCTAssertNil(viewModel.lockScreenAcceptRequest)
        XCTAssertEqual(speech.lastSpokenText, "这个邀请已失效，不需要再回复了")
    }

    /// 邀请期限已过：不等对账，直接告诉他。
    func testLockScreenActionForAnExpiredInviteSaysItIsInvalid() async {
        let (_, appState, _, speech) = makeHome()
        let coordinator = appState.realtimeCoordinator
        coordinator.requestLockScreenInviteAction(.init(
            action: .decline, invite: InviteIdentity(orderId: 32, inviteId: nil, expiresAt: Date().addingTimeInterval(-1))
        ))
        await waitUntil { coordinator.lockScreenInviteAction == nil }

        XCTAssertEqual(speech.lastSpokenText, "这个邀请已失效，不需要再回复了")
    }

    /// 冷启动：按下时首页还没建、WS 接上那一刻协调器会走一次会话清理。意图不能被那次清理抹掉（安全复核 HIGH 1）。
    func testLockScreenActionSurvivesTheColdStartSessionReset() async {
        let appState = AppState()
        let coordinator = appState.realtimeCoordinator
        let target = Self.dispatch(orderId: 51, inviteId: 511)
        coordinator.requestLockScreenInviteAction(Self.lockScreen(.accept, for: target))

        coordinator.attach(to: WebSocketService(), role: .volunteer)  // 冷启动接 WS：detach(clearSessionState: true)
        XCTAssertNotNil(coordinator.lockScreenInviteAction)

        let viewModel = VolunteerHomeViewModel()
        viewModel.configure(with: appState, speechService: SpeechService())
        coordinator.reconcilePendingInvites([target], requestedAt: Date())
        await waitUntil { viewModel.lockScreenAcceptRequest != nil }
        XCTAssertEqual(viewModel.lockScreenAcceptRequest?.orderId, 51)
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

    /// 锁屏那条通知对应的操作：身份取自同一张邀请（`NEW_ORDER` 的 APNs 没有 `inviteId`，只有单号与期限）。
    private static func lockScreen(_ action: InviteNotificationActions.Action, for dispatch: WSNewOrder) -> InviteNotificationActions.Request {
        .init(action: action, invite: InviteIdentity(orderId: dispatch.orderId, inviteId: nil, expiresAt: dispatch.expiresAt?.backendTimestamp))
    }

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

    private func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}
