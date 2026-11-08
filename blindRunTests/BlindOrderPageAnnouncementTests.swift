import Combine
import XCTest
@testable import blindRun

/// 跑者端状态句由谁念（OpenSpec `unify-order-live-tracking` design §6，#887）。
///
/// 负责人 2026-11-08 定：订单页开着、跟着这一单时以订单页那句为准。之前首页和订单页是两个
/// Combine 订阅，谁先投递谁念、没有东西保证顺序。这里**先配首页、再开订单页**，让旧写法下
/// 首页那句先出声（订单页那句随后被 `lastSpokenStatus` 去重挡掉），用例在旧写法下应当红。
///
/// 订单页只经 `openOrderTrackIfNeeded` 打开 track、不走 `configure`：`appState` 为 nil，
/// `loadOrder` 直接返回，Mock 详情不会盖掉用例摆好的订单。
///
/// 只看播报历史分辨不出订单页漏了 `acknowledge` 或报错了 `spoke`：首页那句与订单页同一个目标状态，
/// 会被 `lastSpokenStatus` 去重挡掉，历史照样只有一句。所以每条用例还拿协调器发出的那条更新
/// 直接问 `pageAnnouncement`：等回话的上限设成 5 秒，订单页回过话时答案会立即返回（断言 1 秒内）。
@MainActor
final class BlindOrderPageAnnouncementTests: XCTestCase, BlindRunTestSupport {
    private let orderID: Int64 = 887

    func testIntroCallBackToPendingMatchSpeaksOnlyTheOrderPageSentence() async {
        let fixture = makeFixture(status: .pendingIntroCall, withOrderPage: true)

        fixture.push(from: .pendingIntroCall, to: .pendingMatch)
        await settle()

        XCTAssertEqual(fixture.speech.spokenHistoryForTesting, [BlindIntroCallOutcomeCopy.roundEnded(hadPlan: false)])
        await assertPageAnswer(fixture, is: .pageSpoke)
    }

    func testIntroCallBackToRematchingSpeaksOnlyTheOrderPageSentence() async {
        let fixture = makeFixture(status: .pendingIntroCall, withOrderPage: true)

        fixture.push(from: .pendingIntroCall, to: .rematching)
        await settle()

        XCTAssertEqual(fixture.speech.spokenHistoryForTesting, [BlindIntroCallOutcomeCopy.roundEnded(hadPlan: false)])
        await assertPageAnswer(fixture, is: .pageSpoke)
    }

    func testIntroCallAgreedSpeaksOnlyTheOrderPageSentence() async {
        let fixture = makeFixture(status: .pendingIntroCall, withOrderPage: true)
        let agreed = BlindIntroCallOutcomeCopy.agreed(
            order: makeOrder(orderId: orderID, status: .pendingIntroCall).replacingStatus(with: .pendingAccept)
        )

        fixture.push(from: .pendingIntroCall, to: .pendingAccept)
        await settle()

        XCTAssertEqual(fixture.speech.spokenHistoryForTesting, [agreed])
        await assertPageAnswer(fixture, is: .pageSpoke)
        XCTAssertNotEqual(
            agreed,
            homeSentence(from: .pendingIntroCall, to: .pendingAccept),
            "两句相同的话这条用例分辨不出谁念的"
        )
    }

    /// 订单页开着、跟着这一单，但 `order` 还没拉回来：订单页丢弃这条推送、`acknowledge(spoke: false)`，首页照念。
    func testHomeSpeaksWhenOrderPageHasNoOrderYet() async {
        let fixture = makeFixture(status: .pendingAccept, withOrderPage: true, pageHasOrder: false)

        fixture.push(from: .pendingAccept, to: .driverEnRoute)
        await settle()

        XCTAssertEqual(
            fixture.speech.spokenHistoryForTesting,
            [homeSentence(from: .pendingAccept, to: .driverEnRoute)]
        )
        await assertPageAnswer(fixture, is: .homeShouldSpeak)
    }

    func testHomeSpeaksWhenNoOrderPageIsOpen() async {
        let fixture = makeFixture(status: .pendingAccept, withOrderPage: false)

        fixture.push(from: .pendingAccept, to: .driverEnRoute)
        await settle()

        XCTAssertEqual(
            fixture.speech.spokenHistoryForTesting,
            [homeSentence(from: .pendingAccept, to: .driverEnRoute)]
        )
        await assertPageAnswer(fixture, is: .homeShouldSpeak)
    }

    /// 完成态照现状两边都念：订单页的完成句走独立任务（`acknowledge(spoke: false)`），首页的通用句照念。
    func testCompletionIsSpokenByBothPages() async {
        let fixture = makeFixture(status: .inProgress, withOrderPage: true)
        let homeLine = homeSentence(from: .inProgress, to: .completed)

        fixture.push(from: .inProgress, to: .completed)
        await settle()

        let history = fixture.speech.spokenHistoryForTesting
        XCTAssertEqual(history.count, 2, "应当是首页通用句 + 订单页完成句，实际：\(history)")
        XCTAssertTrue(history.contains(homeLine), "首页那句没念：\(history)")
        await assertPageAnswer(fixture, is: .homeShouldSpeak)
    }

    // MARK: - 辅助

    /// 首页念的那句：它手上的订单换成新状态后的 `blindRunnerAnnouncement()`。
    private func homeSentence(from: RunOrderStatus, to: RunOrderStatus) -> String {
        makeOrder(orderId: orderID, status: from).replacingStatus(with: to).blindRunnerAnnouncement()
    }

    @MainActor
    private struct Fixture {
        let appState: AppState
        let speech: SpeechService
        let home: BlindRunnerHomeViewModel
        let page: BlindOrderStatusViewModel?
        let orderID: Int64
        let captured: CapturedUpdates

        func push(from: RunOrderStatus, to: RunOrderStatus) {
            appState.realtimeCoordinator.simulateIncomingEventForTesting(
                .orderStatusChanged(WSOrderStatusChanged(
                    type: WSMessageType.orderStatusChanged.rawValue,
                    messageId: UUID().uuidString,
                    orderId: orderID,
                    fromStatus: from.rawValue,
                    toStatus: to.rawValue,
                    message: nil,
                    ttsText: nil,
                    priority: "HIGH",
                    timestamp: "2026-11-08T12:00:00Z"
                ))
            )
        }
    }

    private func makeFixture(
        status: RunOrderStatus,
        withOrderPage: Bool,
        pageHasOrder: Bool = true
    ) -> Fixture {
        let appState = AppState()
        appState.currentEnvironment = .mock
        // 等回话的上限放到 5 秒：订单页漏了 `acknowledge` 时，`assertPageAnswer` 会等满它、断言超时而红；
        // 守卫路径漏了时首页在 `settle` 之内一句都念不出来。
        appState.realtimeCoordinator.replaceOrderLiveTrackerForTesting(
            OrderLiveTracker(coordinator: appState.realtimeCoordinator, pollingInterval: 60, announcementTimeout: Self.ackTimeout)
        )
        let captured = CapturedUpdates(appState.realtimeCoordinator)
        let speech = SpeechService()
        speech.isCallActive = { false }

        // 先配首页：旧写法下它的订阅先投递、先念。
        let home = BlindRunnerHomeViewModel(loadTimeout: 0.2)
        home.configure(with: appState, speechService: speech)
        home.activeOrder = makeOrder(orderId: orderID, status: status)

        var page: BlindOrderStatusViewModel?
        if withOrderPage {
            let viewModel = BlindOrderStatusViewModel()
            viewModel.speechService = speech
            if pageHasOrder {
                viewModel.order = makeOrder(orderId: orderID, status: status)
            }
            viewModel.openOrderTrackIfNeeded(appState: appState)
            viewModel.startPolling(orderId: orderID)
            page = viewModel
        }
        appState.realtimeCoordinator.registerActiveOrder(orderID)
        speech.resetSpokenHistoryForTesting()
        return Fixture(appState: appState, speech: speech, home: home, page: page, orderID: orderID, captured: captured)
    }

    private static let ackTimeout: TimeInterval = 5

    /// 拿协调器发出的那条更新问 `pageAnnouncement`。订单页已经回过话就立即返回；漏了就要等满 5 秒。
    private func assertPageAnswer(
        _ fixture: Fixture,
        is expected: PageAnnouncement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        guard let update = fixture.captured.last else {
            XCTFail("协调器没有发出状态更新", file: file, line: line)
            return
        }
        let started = Date()
        let answer = await fixture.appState.realtimeCoordinator.orderLiveTracker.pageAnnouncement(for: update, role: .blind)
        XCTAssertEqual(answer, expected, file: file, line: line)
        XCTAssertLessThan(Date().timeIntervalSince(started), 1, "订单页没有回话，首页等到了上限", file: file, line: line)
    }

    /// 订单页回话后首页立即念；等 0.4 秒，把可能多出来的一句也等进来。
    private func settle() async {
        for _ in 0..<5 { await Task.yield() }
        try? await Task.sleep(nanoseconds: 400_000_000)
    }
}

/// 记下协调器发给首页的那条更新（与订单页收到的是同一个值），用来问 `pageAnnouncement`。
@MainActor
private final class CapturedUpdates {
    private(set) var last: RealtimeOrderStatusUpdate?
    private var subscription: AnyCancellable?

    init(_ coordinator: AppRealtimeCoordinator) {
        subscription = coordinator.statusUpdatePublisher.sink { [weak self] update in self?.last = update }
    }
}
