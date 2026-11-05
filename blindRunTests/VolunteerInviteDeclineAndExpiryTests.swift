import XCTest
import AMapSearchKit
import AVFAudio
import CoreLocation
import SwiftUI
@testable import blindRun

@MainActor
final class VolunteerInviteDeclineAndExpiryTests: XCTestCase, BlindRunTestSupport {
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
