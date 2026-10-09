import Combine
import XCTest
@testable import blindRun

/// 后端「派单与邀请模型」（#371 分批并行 + 60 / 15 分钟期限、#366 待回复列表）在 iOS 侧的适配。
///
/// 期限从「每人 30 秒」变成分钟级之后，原先按秒的倒计时、10 秒的紧迫阈值、按 `orderId` 去重、
/// 不处理撤回，都会让陪跑员看到「还剩 3599 秒回复」或一张点了必定 409 的卡。
@MainActor
final class InviteModelTests: XCTestCase {

    // MARK: - 解码

    /// WS 推送带 `inviteId` / `expiresAt`；整分钟时 `expiresAt` 省掉 `:00`（后端 #542）。
    func testNewOrderDecodesInviteIdentityAndAuthoritativeDeadline() throws {
        let json = #"{"type":"NEW_ORDER","orderId":7,"inviteId":901,"expiresAt":"2026-10-06T10:30","dispatchTimeoutSeconds":900,"requiresIntroCall":false}"#
        let order = try JSONDecoder().decode(WSNewOrder.self, from: Data(json.utf8))
        XCTAssertEqual(order.inviteId, 901)
        XCTAssertEqual(order.expiresAt?.backendTimestamp, "2026-10-06T10:30:00".backendTimestamp)
    }

    /// 待回复列表的每一项**没有 `type`**，多一个 `sentAt`；`distanceKm` 位置未知时是 `null`。
    /// `type` 若还是必填，整个列表都解不出来。
    func testPendingInvitesDecodeWithoutTypeAndWithNullDistance() throws {
        let json = #"""
        {"consecutiveDeclineCount":2,"invites":[
          {"orderId":7,"inviteId":901,"sentAt":"2026-10-06T10:00:00","expiresAt":"2026-10-06T10:15:00",
           "dispatchTimeoutSeconds":900,"distanceKm":null,"requiresIntroCall":true}
        ]}
        """#
        let response = try APIPayloadDecoder.decodePayload(PendingInvitesResponse.self, from: Data(json.utf8), decoder: JSONDecoder())
        XCTAssertEqual(response.consecutiveDeclineCount, 2)
        let invite = try XCTUnwrap(response.invites?.first)
        XCTAssertNil(invite.type)
        XCTAssertNil(invite.distanceKm, "位置未知是 null，不是 0 公里")
        XCTAssertEqual(invite.sentAt, "2026-10-06T10:00:00")
    }

    /// `reason` 是开放枚举：认不出的落 `.other`，不许整条推送解不出来。
    func testWithdrawReasonIsAnOpenEnum() {
        XCTAssertEqual(InviteWithdrawReason(rawValue: "TAKEN"), .taken)
        XCTAssertEqual(InviteWithdrawReason(rawValue: "CONFLICT"), .conflict)
        XCTAssertEqual(InviteWithdrawReason(rawValue: "ORDER_CLOSED"), .orderClosed)
        XCTAssertEqual(InviteWithdrawReason(rawValue: "SOMETHING_NEW"), .other)
        XCTAssertEqual(InviteWithdrawReason(rawValue: nil), .other)
    }

    // MARK: - 协调器

    /// 期限读 `expiresAt`（契约：权威字段），不拿 `dispatchTimeoutSeconds` 推。
    /// 两个值故意差很远：读错了的实现会算出 30 秒后到期。
    func testDeadlineComesFromExpiresAtNotTheTimeoutSeconds() async {
        let now = Date()
        let coordinator = AppRealtimeCoordinator(now: { now })
        let service = WebSocketService()
        coordinator.attach(to: service, role: .volunteer)

        service.simulateIncomingEventForTesting(.newOrder(Self.dispatch(orderId: 1, inviteId: 11, expiresIn: 3600, from: now, timeout: 30)))
        await Task.yield()

        let expiresAt = coordinator.pendingDispatch?.expiresAt.timeIntervalSince(now) ?? 0
        XCTAssertEqual(expiresAt, 3600, accuracy: 1)
    }

    /// 身份是 `inviteId`：同一张单的新邀请替掉旧的；同一张邀请重发不进第二条。
    func testANewInviteForTheSameOrderReplacesTheOldOneButARepeatDoesNot() async {
        let now = Date()
        let coordinator = AppRealtimeCoordinator(now: { now })
        let service = WebSocketService()
        coordinator.attach(to: service, role: .volunteer)

        service.simulateIncomingEventForTesting(.newOrder(Self.dispatch(orderId: 2, inviteId: 21, expiresIn: 600, from: now)))
        service.simulateIncomingEventForTesting(.newOrder(Self.dispatch(orderId: 2, inviteId: 21, expiresIn: 900, from: now)))
        await Task.yield()
        XCTAssertEqual(coordinator.pendingDispatches.count, 1)
        XCTAssertEqual(coordinator.pendingDispatch?.order.inviteId, 21)

        service.simulateIncomingEventForTesting(.newOrder(Self.dispatch(orderId: 2, inviteId: 22, expiresIn: 900, from: now)))
        await Task.yield()
        XCTAssertEqual(coordinator.pendingDispatches.map(\.order.inviteId), [22], "新邀请被当成重复丢掉了")
    }

    /// 撤回只移走**同一张**：同一张单更早一张邀请的迟到撤回，不能把新的那张也带走。
    func testWithdrawalOnlyRemovesTheMatchingInvite() async {
        let now = Date()
        let coordinator = AppRealtimeCoordinator(now: { now })
        let service = WebSocketService()
        coordinator.attach(to: service, role: .volunteer)
        var received: [RealtimeInviteWithdrawal] = []
        let cancellable = coordinator.inviteWithdrawalPublisher.sink { received.append($0) }
        defer { cancellable.cancel() }

        service.simulateIncomingEventForTesting(.newOrder(Self.dispatch(orderId: 3, inviteId: 32, expiresIn: 900, from: now)))
        service.simulateIncomingEventForTesting(.inviteWithdrawn(WSInviteWithdrawn(orderId: 3, inviteId: 31, reason: "TAKEN")))
        await Task.yield()
        XCTAssertEqual(coordinator.pendingDispatches.map(\.order.inviteId), [32], "迟到的旧撤回带走了新邀请")

        service.simulateIncomingEventForTesting(.inviteWithdrawn(WSInviteWithdrawn(orderId: 3, inviteId: 32, reason: "TAKEN")))
        await Task.yield()
        XCTAssertTrue(coordinator.pendingDispatches.isEmpty)
        XCTAssertEqual(received.last, RealtimeInviteWithdrawal(orderId: 3, inviteId: 32, reason: .taken))
    }

    /// 对账：请求发出前就在队列里、快照里没有的 ⇒ 移走；请求在路上时到的 ⇒ 留着；快照里多出来的 ⇒ 补进来。
    func testReconcileRemovesOnlyStaleInvitesAndAddsMissingOnes() async {
        var clock = Date()
        let coordinator = AppRealtimeCoordinator(now: { clock })
        let service = WebSocketService()
        coordinator.attach(to: service, role: .volunteer)

        service.simulateIncomingEventForTesting(.newOrder(Self.dispatch(orderId: 4, inviteId: 41, expiresIn: 900, from: clock)))
        await Task.yield()
        let requestedAt = clock.addingTimeInterval(1)
        clock = clock.addingTimeInterval(2)
        service.simulateIncomingEventForTesting(.newOrder(Self.dispatch(orderId: 5, inviteId: 51, expiresIn: 900, from: clock)))
        await Task.yield()

        coordinator.reconcilePendingInvites(
            [Self.dispatch(orderId: 6, inviteId: 61, expiresIn: 600, from: clock)],
            requestedAt: requestedAt
        )

        XCTAssertEqual(
            Set(coordinator.pendingDispatches.map(\.order.orderId)), [5, 6],
            "4 不在快照里且早于请求 ⇒ 移走；5 在请求之后才到 ⇒ 留着；6 在快照里 ⇒ 补进来"
        )
    }

    // MARK: - 首页那张卡

    /// 正在看的那张被撤回：原地变「已失效」并说原因，按钮不再留在原处。
    func testWithdrawnCurrentInviteTurnsInvalidInPlaceAndSaysWhy() async {
        let (viewModel, appState, service, speech) = makeHome(hubVisible: true)
        _ = appState
        viewModel.incomingOrder = Self.dispatch(orderId: 7, inviteId: 71, expiresIn: 900, from: Date())
        XCTAssertTrue(viewModel.isInviteSheetPresented)

        service.simulateIncomingEventForTesting(.inviteWithdrawn(WSInviteWithdrawn(orderId: 7, inviteId: 71, reason: "TAKEN")))
        await waitUntil { viewModel.currentInvite?.outcome != nil }

        XCTAssertEqual(viewModel.currentInvite?.outcome, .withdrawn(.taken))
        XCTAssertTrue(speech.lastSpokenText?.contains(VolunteerInviteCopy.withdrawnDetail(.taken)) == true)
    }

    /// 他没在看的那张被撤回：静默移除，不再弹一张「已失效」。
    func testWithdrawnInviteThatIsNotOnScreenIsRemovedQuietly() async {
        let (viewModel, appState, service, speech) = makeHome(hubVisible: false)
        _ = appState
        viewModel.incomingOrder = Self.dispatch(orderId: 8, inviteId: 81, expiresIn: 900, from: Date())
        XCTAssertFalse(viewModel.isInviteSheetPresented)

        service.simulateIncomingEventForTesting(.inviteWithdrawn(WSInviteWithdrawn(orderId: 8, inviteId: 81, reason: "ORDER_CLOSED")))
        await waitUntil { viewModel.invites.isEmpty }

        XCTAssertTrue(viewModel.invites.isEmpty)
        XCTAssertFalse(
            speech.spokenHistoryForTesting.contains { $0.contains(VolunteerInviteCopy.expiredTitle) },
            "他没在看的卡失效了却念了一句「已失效」"
        )
    }

    /// 审查 A2：撤回旧邀请（101）之后紧跟着同一张单的新邀请（102）。首页处理撤回时只能清 101，
    /// 按 `orderId` 整单清会把协调器刚收下的 102 一起删掉 —— 新邀请就此丢失。
    func testWithdrawingTheOldInviteDoesNotDropTheNewOneForTheSameOrder() async {
        let (viewModel, appState, service, _) = makeHome(hubVisible: true)
        viewModel.incomingOrder = Self.dispatch(orderId: 12, inviteId: 121, expiresIn: 900, from: Date())

        service.simulateIncomingEventForTesting(.inviteWithdrawn(WSInviteWithdrawn(orderId: 12, inviteId: 121, reason: "TAKEN")))
        service.simulateIncomingEventForTesting(.newOrder(Self.dispatch(orderId: 12, inviteId: 122, expiresIn: 900, from: Date())))
        await waitUntil { viewModel.currentInvite?.order.inviteId == 122 }

        XCTAssertEqual(appState.realtimeCoordinator.pendingDispatches.map(\.order.inviteId), [122], "新邀请被撤回旧邀请时顺手删掉了")
        XCTAssertEqual(viewModel.currentInvite?.order.inviteId, 122)
        XCTAssertTrue(viewModel.currentInvite?.isAwaitingReply == true)
    }

    /// 审查 A3：「去不了」有 5 秒撤销窗口才真正发出，这期间的快照里仍有这一张。
    /// 对账不许把它当新邀请灌回来（卡片重新弹出、撤销时同一张单两张卡）。
    func testSnapshotDuringTheUndoWindowDoesNotResurrectTheDeclinedInvite() async {
        let (viewModel, appState, _, _) = makeHome(hubVisible: true)
        let invite = Self.dispatch(orderId: 13, inviteId: 131, expiresIn: 900, from: Date())
        viewModel.incomingOrder = invite
        viewModel.declineInvite(orderID: 13)
        XCTAssertTrue(viewModel.invites.isEmpty)

        appState.realtimeCoordinator.reconcilePendingInvites([invite], requestedAt: Date())
        try? await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertTrue(appState.realtimeCoordinator.pendingDispatches.isEmpty, "刚拒绝的邀请被快照灌回了协调器")
        XCTAssertTrue(viewModel.invites.isEmpty, "刚拒绝的邀请又弹出来了")

        viewModel.undoPendingDecline()
        XCTAssertEqual(viewModel.invites.filter { $0.id == 13 }.count, 1, "撤销后同一张单出现了两张卡")
    }

    /// 审查 A5：撤销窗口里这张被撤回了，撤销时不能复活一个「接下」按钮。
    func testUndoAfterAWithdrawalRestoresAnInvalidatedCard() async {
        let (viewModel, appState, service, speech) = makeHome(hubVisible: true)
        _ = appState
        viewModel.incomingOrder = Self.dispatch(orderId: 14, inviteId: 141, expiresIn: 900, from: Date())
        viewModel.declineInvite(orderID: 14)

        service.simulateIncomingEventForTesting(.inviteWithdrawn(WSInviteWithdrawn(orderId: 14, inviteId: 141, reason: "TAKEN")))
        try? await Task.sleep(nanoseconds: 300_000_000)
        viewModel.undoPendingDecline()

        XCTAssertEqual(viewModel.currentInvite?.outcome, .withdrawn(.taken))
        XCTAssertTrue(speech.lastSpokenText?.contains(VolunteerInviteCopy.withdrawnDetail(.taken)) == true)
    }

    /// 快照里已没有、且早于请求的卡 ⇒ 失效（离线期间被接走 / 撤回，撤回推送补不回来）。
    func testSnapshotWithoutTheInviteInvalidatesTheCard() async {
        let (viewModel, appState, _, _) = makeHome(hubVisible: true)
        viewModel.incomingOrder = Self.dispatch(orderId: 9, inviteId: 91, expiresIn: 900, from: Date())

        appState.realtimeCoordinator.reconcilePendingInvites([], requestedAt: Date().addingTimeInterval(1))
        await waitUntil { viewModel.currentInvite?.outcome != nil }

        XCTAssertEqual(viewModel.currentInvite?.outcome, .withdrawn(.noLongerPending))
    }

    /// 撤回之后同一张单又发来一张**新**邀请（新 `inviteId`）：替掉那张失效卡，而不是被当成重复丢掉。
    func testANewInviteReplacesTheInvalidatedCardOfTheSameOrder() async {
        let (viewModel, appState, service, _) = makeHome(hubVisible: true)
        _ = appState
        viewModel.incomingOrder = Self.dispatch(orderId: 10, inviteId: 101, expiresIn: 900, from: Date())
        service.simulateIncomingEventForTesting(.inviteWithdrawn(WSInviteWithdrawn(orderId: 10, inviteId: 101, reason: "TAKEN")))
        await waitUntil { viewModel.currentInvite?.outcome != nil }

        service.simulateIncomingEventForTesting(.newOrder(Self.dispatch(orderId: 10, inviteId: 102, expiresIn: 900, from: Date())))
        await waitUntil { viewModel.currentInvite?.order.inviteId == 102 }

        XCTAssertEqual(viewModel.invites.count, 1)
        XCTAssertEqual(viewModel.currentInvite?.order.inviteId, 102)
        XCTAssertTrue(viewModel.currentInvite?.isAwaitingReply == true)
    }

    // MARK: - 对账入口（AppState）

    /// 只对陪跑员：盲人端不许发这条请求。
    func testRestoreSkipsNonVolunteers() async {
        let (appState, orders, persistence) = makeSession(role: .blind)
        defer { persistence.reset() }
        await appState.restorePendingInvites()
        XCTAssertEqual(orders.callCount("pendingInvites()"), 0)
    }

    /// 缺 `invites` 键 ≠「一张都没有」：不能据此把手上的邀请全判失效。
    func testResponseWithoutInvitesKeyDoesNotReconcile() async {
        let (appState, orders, persistence) = makeSession(role: .volunteer)
        defer { persistence.reset() }
        orders.pendingInvitesResult = .success(PendingInvitesResponse(consecutiveDeclineCount: 0, invites: nil))
        var snapshots = 0
        let cancellable = appState.realtimeCoordinator.pendingInviteSnapshotPublisher.sink { _ in snapshots += 1 }
        defer { cancellable.cancel() }

        await appState.restorePendingInvites()

        XCTAssertEqual(orders.callCount("pendingInvites()"), 1)
        XCTAssertEqual(snapshots, 0, "缺键时照空列表对账了")
    }

    func testRestoreReconcilesTheSnapshot() async {
        let (appState, orders, persistence) = makeSession(role: .volunteer)
        defer { persistence.reset() }
        orders.pendingInvitesResult = .success(PendingInvitesResponse(
            consecutiveDeclineCount: 0,
            invites: [Self.dispatch(orderId: 15, inviteId: 151, expiresIn: 600, from: Date())]
        ))

        await appState.restorePendingInvites()

        XCTAssertEqual(appState.realtimeCoordinator.pendingDispatches.map(\.order.inviteId), [151])
    }

    // MARK: - 进度条与紧迫

    /// 恢复回来的邀请 `receivedAt` 是恢复那一刻；分母取完整窗口，进度条才不会在恢复时重新满格。
    func testProgressDenominatorIsTheWholeWindow() {
        let now = Date()
        let invite = VolunteerInviteState(
            order: Self.dispatch(orderId: 11, inviteId: 111, expiresIn: 300, from: now, timeout: 900),
            receivedAt: now,
            expiresAt: now.addingTimeInterval(300),
            remainingSeconds: 300,
            outcome: nil
        )
        XCTAssertEqual(invite.totalSeconds, 900)
        XCTAssertEqual(invite.remainingFraction, 300.0 / 900.0, accuracy: 0.001)
        XCTAssertTrue(invite.isUrgent, "剩 5 分钟，不到 15 分钟")
    }

    // MARK: - Fixture

    private static func dispatch(
        orderId: Int64,
        inviteId: Int64,
        expiresIn seconds: TimeInterval,
        from now: Date,
        timeout: Int = 900
    ) -> WSNewOrder {
        var order = WSNewOrder(
            type: "NEW_ORDER",
            timestamp: nil,
            orderId: orderId,
            startAddress: "深圳湾公园 3 号入口",
            startLatitude: nil,
            startLongitude: nil,
            distanceKm: 3.2,
            plannedStart: nil,
            plannedEnd: nil,
            dispatchTimeoutSeconds: timeout,
            priority: "HIGH",
            pacePreference: nil,
            hasGuideDog: false,
            requiresIntroCall: false
        )
        order.inviteId = inviteId
        order.expiresAt = DateFormatter.aidRunBackendLocalDateTime.string(from: now.addingTimeInterval(seconds))
        return order
    }

    /// 返回 `AppState` 让调用方攥着：view model 对它是 `weak`。
    private func makeHome(hubVisible: Bool) -> (VolunteerHomeViewModel, AppState, WebSocketService, SpeechService) {
        let appState = AppState()
        let service = WebSocketService()
        appState.realtimeCoordinator.attach(to: service, role: .volunteer)
        let speech = SpeechService()
        let viewModel = VolunteerHomeViewModel()
        viewModel.configure(with: appState, speechService: speech)
        viewModel.isDispatchHubVisible = hubVisible
        return (viewModel, appState, service, speech)
    }

    private func makeSession(role: UserRole) -> (AppState, FakeOrderService, UserDefaultsAppStatePersistence) {
        let orders = FakeOrderService()
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        // 内存 token 库：`accessToken` 的 didSet 会落库，用真 Keychain 会污染设备。
        let appState = AppState(orders: orders, persistence: persistence, tokenStore: InMemoryTokenStore())
        appState.accessToken = "token"
        appState.userId = 42
        appState.activeRole = role
        return (appState, orders, persistence)
    }

    private func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}
