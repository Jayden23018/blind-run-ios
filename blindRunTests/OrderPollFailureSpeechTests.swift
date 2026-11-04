import XCTest
@testable import blindRun

/// 订单页轮询失败只播一次，恢复时播一次（#659，审计 F-9）。
///
/// 跑步中进地下通道时，5 秒一轮的轮询每轮都失败。原来每轮都念错误并震动，
/// 同一句话一直占着盲人听车流的耳朵。每条用例直接调 `loadOrder` 模拟一轮轮询。
///
/// **验红方式**：把 `OrderPollFailureGate.reportFailure` 改成每轮都念、`reportSuccess` 改成从不念，
/// 前三条必须失败；去掉 `lastSpokenStatus` 那个条件，第五条必须失败；去掉 `Task.isCancelled` 那道 guard，第六条必须失败。
@MainActor
final class OrderPollFailureSpeechTests: XCTestCase {

    private static let orderId: Int64 = 659
    private static let offline = APIError.networkError(URLError(.notConnectedToInternet))

    /// view model 对 `AppState` 是 `weak`，测试自己攥着（记忆 `location-service-test-seam-and-weak-viewmodel-deps`）。
    private var appState: AppState?

    func testConsecutiveFailuresSpeakOnlyOnce() async {
        let (viewModel, service, speech) = makeViewModel()
        service.orderDetailResults = [.failure(Self.offline), .failure(Self.offline), .failure(Self.offline)]

        for _ in 0..<3 { await viewModel.loadOrder(orderId: Self.orderId, speakChanges: true) }

        XCTAssertEqual(speech.spokenHistoryForTesting, [Self.offline.localizedMessage])
        XCTAssertEqual(viewModel.errorMessage, Self.offline.localizedMessage, "屏幕上的错误文字仍要每轮都在")
    }

    func testRecoverySpeaksOnceAndOnlyOnce() async {
        let (viewModel, service, speech) = makeViewModel()
        service.orderDetailResults = [
            .failure(Self.offline), .failure(Self.offline),
            .success(Self.order(.pendingMatch)), .success(Self.order(.pendingMatch))
        ]

        for _ in 0..<4 { await viewModel.loadOrder(orderId: Self.orderId, speakChanges: true) }

        XCTAssertEqual(
            speech.spokenHistoryForTesting,
            [Self.offline.localizedMessage, OrderPollFailureGate.recoveredAnnouncement]
        )
        XCTAssertNil(viewModel.errorMessage)
    }

    /// 恢复之后再断：这是新的一段失败，要再播一次。用来分辨「整个页面只播一次」这种过严的实现。
    func testANewFailureAfterRecoverySpeaksAgain() async {
        let (viewModel, service, speech) = makeViewModel()
        service.orderDetailResults = [.failure(Self.offline), .success(Self.order(.pendingMatch)), .failure(Self.offline)]

        for _ in 0..<3 { await viewModel.loadOrder(orderId: Self.orderId, speakChanges: true) }

        XCTAssertEqual(
            speech.spokenHistoryForTesting,
            [Self.offline.localizedMessage, OrderPollFailureGate.recoveredAnnouncement, Self.offline.localizedMessage]
        )
    }

    /// 恢复那一轮状态变了：新状态那句已经说明连上了，不再补一句把它切断。
    func testStatusChangeOnRecoveryIsNotCutOffByTheRecoveryLine() async {
        let (viewModel, service, speech) = makeViewModel()
        service.orderDetailResults = [.failure(Self.offline), .success(Self.order(.scheduledConfirmed))]

        for _ in 0..<2 { await viewModel.loadOrder(orderId: Self.orderId, speakChanges: true) }

        XCTAssertEqual(speech.spokenHistoryForTesting.count, 2, "\(speech.spokenHistoryForTesting)")
        XCTAssertEqual(speech.spokenHistoryForTesting.first, Self.offline.localizedMessage)
        XCTAssertNotEqual(speech.spokenHistoryForTesting.last, OrderPollFailureGate.recoveredAnnouncement)
    }

    /// 恢复那一轮状态变了，但新状态别处已经念过（`lastSpokenStatus` 去重）：状态句不会出声，恢复句必须照念。
    func testRecoveryIsSpokenWhenTheNewStatusWasAlreadyAnnounced() async {
        let (viewModel, service, speech) = makeViewModel()
        speech.markStatusAnnounced(.scheduledConfirmed)
        service.orderDetailResults = [.failure(Self.offline), .success(Self.order(.scheduledConfirmed))]

        for _ in 0..<2 { await viewModel.loadOrder(orderId: Self.orderId, speakChanges: true) }

        XCTAssertEqual(
            speech.spokenHistoryForTesting,
            [Self.offline.localizedMessage, OrderPollFailureGate.recoveredAnnouncement]
        )
    }

    /// 轮询任务被取消（`startPolling` 重入时先 `cancel()` 旧任务）不算失败：不念、也不记，
    /// 否则下一轮成功会念一句不存在的「连接恢复了」。
    func testCancelledPollIsNeitherSpokenNorCountedAsAFailure() async {
        let speech = SpeechService()
        speech.isCallActive = { false }
        let task = Task { @MainActor () -> OrderPollFailureGate in
            var gate = OrderPollFailureGate()
            gate.reportFailure("网络连接失败", orderId: Self.orderId, to: speech)
            return gate
        }
        task.cancel()

        let gate = await task.value

        XCTAssertNil(gate.failingOrderId)
        XCTAssertTrue(speech.spokenHistoryForTesting.isEmpty, "\(speech.spokenHistoryForTesting)")
    }

    // MARK: - Fixture

    private func makeViewModel() -> (BlindOrderStatusViewModel, FakeOrderService, SpeechService) {
        let service = FakeOrderService()
        let appState = AppState(orders: service)
        appState.currentEnvironment = .mock
        self.appState = appState
        let speech = SpeechService()
        speech.isCallActive = { false }
        let viewModel = BlindOrderStatusViewModel()
        viewModel.configure(appState: appState, speechService: speech)
        viewModel.order = Self.order(.pendingMatch)
        speech.resetSpokenHistoryForTesting()
        return (viewModel, service, speech)
    }

    private static func order(_ status: RunOrderStatus) -> OrderDetailResponse {
        OrderDetailResponse.preview(orderId: orderId, status: status)
    }
}
