import XCTest
import AMapSearchKit
import AVFAudio
import CoreLocation
import SwiftUI
@testable import blindRun

@MainActor
final class VolunteerHomeDispatchTests: XCTestCase, BlindRunTestSupport {
    func testVolunteerHomeCoalescesLifecycleReconnectAndManualRefreshWhileKeepingContent() async throws {
        let client = CancellationSuspendingAPIClient()
        let appState = AppState(apiClient: client)
        let existingSummary = try JSONDecoder().decode(
            VolunteerDispatchSummaryResponse.self,
            from: Data(#"{"canDispatch":true,"notAvailableReasons":[],"wantsDispatch":true}"#.utf8)
        )
        let existingOrder = makeOrder(orderId: 702, status: .driverEnRoute)
        let viewModel = VolunteerHomeViewModel(dispatchPropagationDelay: 0, loadTimeout: 0.08)
        viewModel.configure(with: appState, speechService: SpeechService())
        viewModel.dispatchSummary = existingSummary
        viewModel.activeOrder = existingOrder
        let startedAt = Date()

        let lifecycleLoad = Task {
            await viewModel.load(currentLocation: nil, locationAuthorized: false)
        }
        let didStart = await waitUntil {
            client.requestCount(for: "/api/volunteer/dispatch-summary") == 1
        }
        let reconnectLoad = Task {
            await viewModel.load(currentLocation: nil, locationAuthorized: false)
        }
        let manualRefresh = Task { await viewModel.refreshDispatchSummary() }
        await lifecycleLoad.value
        await reconnectLoad.value
        await manualRefresh.value

        XCTAssertTrue(didStart)
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 0.5)
        XCTAssertEqual(client.requestCount(for: "/api/volunteer/dispatch-summary"), 1)
        XCTAssertEqual(viewModel.dispatchSummary?.canDispatch, true)
        XCTAssertEqual(viewModel.activeOrder?.orderId, existingOrder.orderId)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(viewModel.dispatchSummaryErrorMessage, "加载超过 20 秒，请重试。")
    }

    func testVolunteerDispatchSummaryDoesNotWaitForSlowProfileHydration() async {
        // 两个替身各管一片：慢的那半是资料水合（认证片，走 apiClient），
        // 快的那半是派单摘要（订单片，走 orders）。
        let client = Self.makeDispatchSummaryService(
            first: .success(Self.dispatchSummaryAvailable),
            rest: Self.dispatchSummaryAvailable
        )
        let appState = AppState(apiClient: SlowProfileHydrationAPIClient(), orders: client)
        let viewModel = VolunteerHomeViewModel(dispatchPropagationDelay: 0, loadTimeout: 2)
        viewModel.configure(with: appState, speechService: SpeechService())

        let loadTask = Task { await viewModel.load(currentLocation: nil, locationAuthorized: false) }
        let didLoadSummary = await waitUntil(timeout: 0.5) {
            viewModel.dispatchSummary?.canDispatch == true && !viewModel.isLoading
        }

        XCTAssertTrue(didLoadSummary)
        XCTAssertEqual(client.callCount("dispatchSummary()"), 1)
        loadTask.cancel()
        await loadTask.value
    }

    /// 接下之后**卡片原地变「已约好」，不自动跳订单页**（设计交付 v3 §4.4.3）。
    ///
    /// 🔴 **这条用例 2026-09-17 改过方向。** 它原先断言 `acceptedDispatchOrderId == 1`
    /// 会在接单成功那一刻出现 —— 那正是「自动 push」的实现。改成邀请卡之后自动跳会把
    /// 那张确认卡一闪而过，而它是唯一一处告诉陪跑员「跑者的全名和电话已经放进订单」的地方。
    ///
    /// 所以断言拆成两段：**成功那一刻不导航**，**点了「查看订单」才导航**。
    /// 只留后半段的话，一个仍然自动跳的实现照样能过。
    func testAcceptingDispatchShowsTheBookedCardAndOnlyNavigatesOnTap() async throws {
        let appState = AppState()
        appState.currentEnvironment = .mock
        appState.updateVolunteerProfile(makeApprovedVolunteerProfile())
        let speechService = SpeechService()
        let viewModel = VolunteerHomeViewModel()
        viewModel.configure(with: appState, speechService: speechService)
        viewModel.incomingOrder = makeDispatchOrder(orderId: 1)
        viewModel.dispatchCountdown = 30

        viewModel.respondToDispatch(
            action: .accept,
            currentLocation: CLLocationCoordinate2D(latitude: 39.905, longitude: 116.408),
            locationAuthorized: true
        )

        // 等到**整条链路跑完**（`isRespondingToDispatch` 在最后一次刷新之后才落回 false）。
        // 只等 `outcome == .accepted` 是不够的：结果先落在卡上、刷新在后面，
        // 那一刻 `acceptedDispatchInitialOrder` 还没回来。
        let didBook = await waitUntil {
            viewModel.currentInvite?.outcome == .accepted && !viewModel.isRespondingToDispatch
        }
        XCTAssertTrue(didBook)
        XCTAssertNil(
            viewModel.acceptedDispatchOrderId,
            "接下成功那一刻不该导航 —— 结果卡还没被看到"
        )
        XCTAssertEqual(viewModel.acceptedDispatchInitialOrder?.orderId, 1)
        XCTAssertEqual(viewModel.acceptedDispatchInitialOrder?.status, .pendingAccept)
        XCTAssertEqual(viewModel.activeOrder?.orderId, 1)
        XCTAssertEqual(viewModel.activeOrder?.status, .pendingAccept)
        XCTAssertNotNil(viewModel.incomingOrder, "结果卡还在，邀请不该从队列里消失")
        XCTAssertEqual(speechService.lastSpokenText, "已接受订单")

        viewModel.openAcceptedOrder(orderID: 1)

        XCTAssertEqual(viewModel.acceptedDispatchOrderId, 1)
        XCTAssertNil(viewModel.incomingOrder)
        XCTAssertFalse(viewModel.isInviteSheetPresented)
    }

    func testAcceptingDispatchFailureDoesNotPublishNavigationOrderId() async throws {
        let appState = AppState()
        appState.currentEnvironment = .mock
        appState.updateVolunteerProfile(makeApprovedVolunteerProfile())
        let viewModel = VolunteerHomeViewModel()
        viewModel.configure(with: appState, speechService: SpeechService())
        viewModel.incomingOrder = makeDispatchOrder(orderId: 999)
        viewModel.dispatchCountdown = 30

        viewModel.respondToDispatch(
            action: .accept,
            currentLocation: CLLocationCoordinate2D(latitude: 39.905, longitude: 116.408),
            locationAuthorized: true
        )

        let didFail = await waitUntil { viewModel.errorMessage != nil }
        XCTAssertTrue(didFail)
        XCTAssertNil(viewModel.acceptedDispatchOrderId)
        XCTAssertNotNil(viewModel.incomingOrder)
        XCTAssertEqual(viewModel.dispatchCountdown, 30)
        XCTAssertFalse(viewModel.isRespondingToDispatch)
    }

    func testAcceptingDispatchRequiresReadinessAndLocation() async throws {
        let unavailableState = AppState()
        unavailableState.currentEnvironment = .mock
        unavailableState.updateVolunteerProfile(makeApprovedVolunteerProfile(isAvailable: false))
        let unavailableViewModel = VolunteerHomeViewModel()
        unavailableViewModel.configure(with: unavailableState, speechService: SpeechService())
        unavailableViewModel.incomingOrder = makeDispatchOrder(orderId: 1)

        unavailableViewModel.respondToDispatch(
            action: .accept,
            currentLocation: CLLocationCoordinate2D(latitude: 39.905, longitude: 116.408),
            locationAuthorized: true
        )

        XCTAssertEqual(unavailableViewModel.errorMessage, "请先开启可服务状态")
        XCTAssertNil(unavailableViewModel.acceptedDispatchOrderId)
        XCTAssertNotNil(unavailableViewModel.incomingOrder)

        let noLocationState = AppState()
        noLocationState.currentEnvironment = .mock
        noLocationState.updateVolunteerProfile(makeApprovedVolunteerProfile())
        let noLocationViewModel = VolunteerHomeViewModel()
        noLocationViewModel.configure(with: noLocationState, speechService: SpeechService())
        noLocationViewModel.incomingOrder = makeDispatchOrder(orderId: 1)

        noLocationViewModel.respondToDispatch(
            action: .accept,
            currentLocation: nil,
            locationAuthorized: false
        )

        XCTAssertEqual(noLocationViewModel.errorMessage, "需要开启定位权限才能接单")
        XCTAssertNil(noLocationViewModel.acceptedDispatchOrderId)
        XCTAssertNotNil(noLocationViewModel.incomingOrder)
    }

    /// 推送说「这一单可以直接接」，后端却回 409 `INTRO_CALL_REQUIRED`。
    ///
    /// 成因是竞态：推送是后端判断的一个**快照**，发出之后这一对的磨合记录或
    /// `app.intro-call.enabled` 都可能变。志愿者已经点过这个动作了，30 秒倒计时里不该让他
    /// 再点一遍 —— 客户端自己改发 `INTERESTED`，并照常进通话页。
    ///
    /// 断言打在**发出去的动作序列**上，不是打在「最后成功了」上：只看结果的话，
    /// 一个从头到尾只发 `INTERESTED` 的实现也能过。
    func testAcceptRejectedByTheIntroCallGuardSilentlyFallsBackToInterested() async throws {
        let client = IntroCallRequiredOnAcceptAPIClient()
        let appState = AppState(apiClient: client)
        appState.currentEnvironment = .mock
        appState.updateVolunteerProfile(makeApprovedVolunteerProfile())
        let speechService = SpeechService()
        let viewModel = VolunteerHomeViewModel()
        viewModel.configure(with: appState, speechService: speechService)
        let order = makeDispatchOrder(orderId: 77, requiresIntroCall: false)
        XCTAssertEqual(order.dispatchRespondAction, .accept)
        viewModel.incomingOrder = order
        viewModel.dispatchCountdown = 30

        viewModel.respondToDispatch(
            action: order.dispatchRespondAction,
            currentLocation: CLLocationCoordinate2D(latitude: 39.905, longitude: 116.408),
            locationAuthorized: true
        )

        let didFallBack = await waitUntil { viewModel.pendingIntroCallOrder != nil }
        XCTAssertTrue(didFallBack)
        XCTAssertEqual(client.respondActions, [.accept, .interested])
        XCTAssertNil(viewModel.acceptedDispatchOrderId)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNil(viewModel.incomingOrder)
        XCTAssertEqual(speechService.lastSpokenText, "已告诉跑者你有意向，请留意他的来电")
    }

    /// 「这次去不了」走的是**延时发送**：卡片立刻收起，请求要等撤销窗口过完才发出去
    /// （设计交付 v3 §4.4.3「5 秒内可撤销」）。
    ///
    /// 🔴 **只能这么实现。** 后端 `POST /{id}/respond` 只有三个 action，
    /// `handleDecline` 一进去就把这一单推给下一个人，**没有任何撤销入口**
    /// （`DispatchService.java:602-623`）。先发再撤是撤不回来的 ⇒
    /// 「撤销」只能实现成「还没发」。
    ///
    /// 断言打在**请求有没有发出去**上，不是打在「卡片收起来了」上：
    /// 一个立刻就发、只是把卡片藏起来的实现同样会让卡片收起，而那个实现里撤销是假的。
    func testDecliningAnInviteHoldsTheRequestUntilTheUndoWindowCloses() async throws {
        let client = RecordingRespondAPIClient()
        let appState = AppState(apiClient: client)
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let viewModel = VolunteerHomeViewModel(declineUndoWindow: 0.3)
        viewModel.configure(with: appState, speechService: speechService)
        viewModel.incomingOrder = makeDispatchOrder(orderId: 1)

        viewModel.declineInvite(orderID: 1)

        // 窗口里：卡片已经收起，而请求**一条都没发**。
        XCTAssertNil(viewModel.incomingOrder)
        XCTAssertEqual(viewModel.pendingDecline?.id, 1)
        XCTAssertTrue(client.respondActions.isEmpty, "撤销窗口还没过完就把 DECLINE 发出去了")
        XCTAssertNil(viewModel.acceptedDispatchOrderId)
        XCTAssertEqual(speechService.lastSpokenText, "已回复这次去不了，0秒内可以撤销")

        let didSend = await waitUntil { client.respondActions == [.decline] }
        XCTAssertTrue(didSend, "撤销窗口过完之后 DECLINE 必须真的发出去")
        XCTAssertNil(viewModel.pendingDecline)
    }

    /// 窗口里点「撤销」：一条请求都不发，邀请回到队列。
    func testUndoingADeclineSendsNothingAndPutsTheInviteBack() async throws {
        let client = RecordingRespondAPIClient()
        let appState = AppState(apiClient: client)
        appState.currentEnvironment = .mock
        let viewModel = VolunteerHomeViewModel(declineUndoWindow: 5)
        viewModel.configure(with: appState, speechService: SpeechService())
        viewModel.incomingOrder = makeDispatchOrder(orderId: 1)

        viewModel.declineInvite(orderID: 1)
        viewModel.undoPendingDecline()

        XCTAssertNil(viewModel.pendingDecline)
        XCTAssertEqual(viewModel.incomingOrder?.orderId, 1)
        XCTAssertTrue(viewModel.isInviteSheetPresented)

        // 再等一个撤销窗口，确认那条延时请求**真的被取消了**，
        // 而不是只把 `pendingDecline` 清空、任务还在后面自己跑完。
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertTrue(client.respondActions.isEmpty, "撤销之后还是把 DECLINE 发出去了")
    }

    /// 连续 3 次**真的发出去**的「去不了」之后，接单主页那句不带惩罚的询问才出现；
    /// 接下任一单即清零（设计交付 v3 §4.4.3 / §10「连续 3 次」）。
    ///
    /// 🚩 **撤销掉的那次不算。** 他并没有拒绝这一单。
    func testThreeSentDeclinesAskAboutAvailabilityAndAcceptingClearsIt() async throws {
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        defer { persistence.reset() }
        let client = RecordingRespondAPIClient()
        let appState = AppState(apiClient: client, persistence: persistence)
        appState.currentEnvironment = .mock
        appState.userId = 42  // 次数按账号记（#552），没有账号就不落盘
        appState.updateVolunteerProfile(makeApprovedVolunteerProfile())
        let viewModel = VolunteerHomeViewModel(declineUndoWindow: 0)
        viewModel.configure(with: appState, speechService: SpeechService())

        // 撤销掉的那一次不计数。
        viewModel.incomingOrder = makeDispatchOrder(orderId: 90)
        viewModel.declineInvite(orderID: 90)
        viewModel.undoPendingDecline()
        XCTAssertFalse(viewModel.shouldAskAboutAvailability)

        for orderId in Int64(91)...Int64(93) {
            viewModel.incomingOrder = makeDispatchOrder(orderId: orderId)
            viewModel.declineInvite(orderID: orderId)
            let didSend = await waitUntil { viewModel.pendingDecline == nil }
            XCTAssertTrue(didSend)
        }

        XCTAssertTrue(viewModel.shouldAskAboutAvailability)

        viewModel.incomingOrder = makeDispatchOrder(orderId: 1)
        viewModel.respondToDispatch(
            action: .accept,
            currentLocation: CLLocationCoordinate2D(latitude: 39.905, longitude: 116.408),
            locationAuthorized: true
        )
        let didBook = await waitUntil { viewModel.currentInvite?.outcome == .accepted }
        XCTAssertTrue(didBook)
        XCTAssertFalse(viewModel.shouldAskAboutAvailability, "接下一单就该清零")
    }

    func testVolunteerHomeReceivesDispatchWhenWebSocketIsAssignedAfterConfigure() async throws {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let viewModel = VolunteerHomeViewModel()

        viewModel.configure(with: appState, speechService: speechService)
        // 🔴 **这一位是 2026-09-18 §4.4.1 落地（PR #161）之后才成为前提的，当时漏了这条用例。**
        // 呈现档由 `VolunteerInvitePresentation.resolve` 按「他此刻在哪一页」决定：
        // 不在接单主页就是**横幅**档，而横幅档 `makesSound == false`、
        // `isInviteSheetPresented` 也不置位 ⇒ 下面两条断言必挂。
        // 本条用例验的是**时序**（WebSocket 在 `configure` 之后才挂上也能收到派单），
        // 呈现档只是它的舞台，所以把舞台钉成邀请卡那一档，而不是改断言去将就。
        viewModel.isDispatchHubVisible = true

        let webSocketService = WebSocketService()
        appState.webSocketService = webSocketService
        webSocketService.simulateIncomingEventForTesting(.newOrder(makeDispatchOrder(orderId: 42)))

        let didReceive = await waitUntil { viewModel.incomingOrder?.orderId == 42 }
        XCTAssertTrue(didReceive)
        XCTAssertEqual(viewModel.dispatchCountdown, 30)
        XCTAssertTrue(viewModel.isInviteSheetPresented)
        // 与推送标题、弹层标题同一个词（设计交付 v3 §6）——
        // 用户是被那条推送叫过来的，三处不同名会让人以为点开的是别的东西。
        //
        // 🚩 **等一拍再断言**：提示音与播报刻意让出了弹卡那一帧（见 `enqueue` 里那段注释），
        // 所以它们落在下一个 runloop 上。同步断言会偶发地读到还没写进去的值。
        let didSpeak = await waitUntil {
            speechService.lastSpokenText == "新的陪跑邀请，还剩 30 秒回复" // 与卡片共用 `replyCountdown`（#371），30 秒仍按秒说
        }
        XCTAssertTrue(didSpeak, "播报没发出来，实际是 \(speechService.lastSpokenText ?? "nil")")
    }

    /// 回复窗口走完：卡片**原地**变「这个邀请已失效」，而**一条 `/respond` 都不发**
    /// （设计交付 v3 §4.4.3 最后一行）。
    ///
    /// 🔴 **不发才是对的。** 后端 `app.dispatch.per-volunteer-timeout-seconds` 到点自己
    /// `dispatchToNext`（`DispatchScheduler.java:140-143`），这一单那一刻已经不归他了 ⇒
    /// 客户端再补一条 `DECLINE` 只会撞 409，而那个错误既没法处理也不该弹给用户。
    /// 此前的实现在倒计时归零时会自动发一条。
    ///
    /// 断言打在**请求计数**上而不是「卡片变灰了」：一个照发不误、只是顺手改了文案的实现
    /// 同样会让卡片变灰。
    func testAnInviteThatRunsOutOfTimeExpiresInPlaceWithoutSendingAnything() async throws {
        let client = RecordingRespondAPIClient()
        let appState = AppState(apiClient: client)
        appState.currentEnvironment = .mock
        let viewModel = VolunteerHomeViewModel()
        viewModel.configure(with: appState, speechService: SpeechService())

        let webSocketService = WebSocketService()
        appState.webSocketService = webSocketService
        webSocketService.simulateIncomingEventForTesting(
            .newOrder(makeDispatchOrder(orderId: 42, dispatchTimeoutSeconds: 1))
        )

        let didReceive = await waitUntil { viewModel.incomingOrder?.orderId == 42 }
        XCTAssertTrue(didReceive)

        let didExpire = await waitUntil(timeout: 4) { viewModel.currentInvite?.outcome == .expired }
        XCTAssertTrue(didExpire, "回复窗口走完之后这张卡应该原地变成「已失效」")
        XCTAssertTrue(client.respondActions.isEmpty, "超时那一刻不该再发任何 /respond")
        XCTAssertEqual(viewModel.currentInvite?.remainingSeconds, 0)
        XCTAssertTrue(
            viewModel.invitesAwaitingReply.isEmpty,
            "已失效的那张不该再算进「待回复」——接单主页的入口会因此一直亮着"
        )

        // 点「知道了」之后才收掉。
        viewModel.dismissInvite(orderID: 42)
        XCTAssertNil(viewModel.incomingOrder)
        XCTAssertFalse(viewModel.isInviteSheetPresented)
    }

    /// 志愿者资料水合**慢**，而派单摘要要照常先出来。
    ///
    /// 它仍然是传输桩，因为它演的是**认证·会话片**那两条端点
    /// （`AuthServing.volunteerProfile` / `.volunteerRegistrationStatus`）——
    /// 订单片这次不动它们。派单摘要那一半已经交给 `FakeOrderService`，
    /// 所以这里只剩「挂住 5 秒」这一件事。
    private final class SlowProfileHydrationAPIClient: APIClientProtocol, @unchecked Sendable {
        func request<T: Decodable>(
            method: HTTPMethod,
            path: String,
            query: [String: String]?,
            body: (any Encodable & Sendable)?,
            requiresAuth: Bool
        ) async throws -> T {
            try await Task.sleep(nanoseconds: 5_000_000_000)
            throw APIError.invalidURL
        }

        func upload<T: Decodable>(
            path: String,
            query: [String: String]?,
            fields: [String: String]?,
            files: [MultipartFile],
            requiresAuth: Bool
        ) async throws -> T {
            throw APIError.invalidURL
        }
    }

    /// `/respond` 收到 `ACCEPT` 就回 409 `INTRO_CALL_REQUIRED`，`INTERESTED` 照单全收 ——
    /// 后端 `DispatchService.handleAccept` 那道守卫的最小复刻。记录动作序列，
    /// 因为「有没有先试过 ACCEPT」只有序列看得出来。
    private final class IntroCallRequiredOnAcceptAPIClient: APIClientProtocol, @unchecked Sendable {
        private(set) var respondActions: [OrderRespondAction] = []

        func request<T: Decodable>(
            method: HTTPMethod,
            path: String,
            query: [String: String]?,
            body: (any Encodable & Sendable)?,
            requiresAuth: Bool
        ) async throws -> T {
            guard method == .post, path.hasSuffix("/respond"),
                  let request = body as? OrderRespondRequest else {
                throw APIError.invalidURL
            }
            respondActions.append(request.action)
            if request.action == .accept {
                throw APIError.serverError(ErrorResponse(
                    code: "INTRO_CALL_REQUIRED",
                    message: "需要先与跑者通话"
                ))
            }
            guard let value = EmptyResponse() as? T else { throw APIError.invalidURL }
            return value
        }

        func upload<T: Decodable>(
            path: String,
            query: [String: String]?,
            fields: [String: String]?,
            files: [MultipartFile],
            requiresAuth: Bool
        ) async throws -> T {
            throw APIError.invalidURL
        }
    }

    /// 只记「`/respond` 收到了哪些 action」，全部成功。
    ///
    /// 撤销窗口那两条用例断言的是**请求有没有发出去**，所以桩必须记下调用而不是只记结果 ——
    /// 一个立刻就发、只是把卡片藏起来的实现，从结果上看和正确实现一模一样。
    private final class RecordingRespondAPIClient: APIClientProtocol, @unchecked Sendable {
        private(set) var respondActions: [OrderRespondAction] = []

        func request<T: Decodable>(
            method: HTTPMethod,
            path: String,
            query: [String: String]?,
            body: (any Encodable & Sendable)?,
            requiresAuth: Bool
        ) async throws -> T {
            guard method == .post, path.hasSuffix("/respond"),
                  let request = body as? OrderRespondRequest else {
                throw APIError.invalidURL
            }
            respondActions.append(request.action)
            guard let value = EmptyResponse() as? T else { throw APIError.invalidURL }
            return value
        }

        func upload<T: Decodable>(
            path: String,
            query: [String: String]?,
            fields: [String: String]?,
            files: [MultipartFile],
            requiresAuth: Bool
        ) async throws -> T {
            throw APIError.invalidURL
        }
    }
}
