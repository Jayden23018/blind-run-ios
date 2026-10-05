import XCTest
@testable import blindRun

/// 盲人端汇合屏的「开始跑步」（后端 #307 同意闸 + #346 盲人可调 `start-service`）。
///
/// 此前这一屏的主按钮是「打电话给张伟」，理由是「盲人 token 调不了 `/start-service`」。
/// 那个理由自 #346 起不成立，而它留下的后果是：同意闸在盲人这一侧没有任何入口，
/// 陪跑员每一单都只能等到约定开跑 + 15 分钟才能强制开始。
@MainActor
final class BlindStartRunTests: XCTestCase {

    // MARK: - 主按钮

    func testMetUpPrimaryActionIsStartRunEvenWhenTheVolunteerIsDialable() {
        let presentation = make(.driverArrived, volunteerPhone: "13800000001")
        XCTAssertEqual(presentation.primaryAction, .startRun)
        XCTAssertEqual(presentation.primaryAction?.title, "开始跑步")
        XCTAssertEqual(presentation.primaryAction?.isEnabled, true)
    }

    /// 号码为 null 时主按钮版位以前是空的（`BlindRunPhaseTests` 记过这个缺口）。
    /// 「开始跑步」不依赖号码，版位恒有。
    func testMetUpPrimaryActionDoesNotDependOnAPhoneNumber() {
        XCTAssertEqual(make(.driverArrived, volunteerPhone: nil).primaryAction, .startRun)
    }

    /// 出发态仍然是打电话：人还没到，没有「开始」可言。
    func testDepartedStillOffersTheCall() {
        XCTAssertEqual(
            make(.driverEnRoute, volunteerPhone: "13800000001").primaryAction,
            .callVolunteer(title: "打电话给张")
        )
    }

    // MARK: - 文案

    func testMetUpSubtitlePointsToTheButtonBelow() {
        let subtitle = make(.driverArrived).subtitle
        XCTAssertTrue(subtitle.contains("见面后，轻点下方开始跑步"), "实际：\(subtitle)")
        XCTAssertFalse(subtitle.contains("等待志愿者开始服务"), "还在叫盲人等对方开始：\(subtitle)")
    }

    /// 首页与语音状态查询不在订单页上 ⇒ 不许说「轻点下方」；也不许再说「等待志愿者开始服务」。
    func testArrivalCopyOutsideTheOrderPageNamesTheActionWithoutAScreenPosition() {
        let copies = [
            RunOrderStatus.driverArrived.blindRunnerDescription,
            RunOrderStatus.driverArrived.blindRunnerAnnouncement,
            SpeechService.statusAnnouncement(for: .driverArrived),
        ]
        for copy in copies {
            XCTAssertFalse(copy.contains("轻点下方"), "离开订单页也在指屏幕位置：\(copy)")
            XCTAssertFalse(copy.contains("等待志愿者开始服务"), "仍在叫盲人等对方开始：\(copy)")
            XCTAssertTrue(copy.contains("开始跑步"), "没说出能做的那件事：\(copy)")
        }
    }

    /// 陪跑员那一侧被同意闸拦下时听到的那句，要能让他转告跑者按哪个按钮。
    func testVolunteerConsentPendingCopyNamesTheRunnerButton() {
        XCTAssertTrue(ErrorCode.blindConfirmationPending.localizedMessage.contains("开始跑步"))
    }

    // MARK: - 动作

    func testStartRunCallsStartServiceOnceAndReloadsTheOrder() async {
        let service = makeOrderService(reloadStatus: .inProgress)
        let (viewModel, appState) = makeViewModel(service: service, status: .driverArrived)
        _ = appState

        await viewModel.startRun()

        XCTAssertEqual(service.callCount("startService(orderId:)"), 1)
        XCTAssertEqual(service.lastOrderId, 701)
        XCTAssertEqual(service.callCount("orderDetail(orderId:)"), 1, "开跑成功后没有重拉订单，倒计时不会开始")
        XCTAssertEqual(viewModel.order?.status, .inProgress)
        XCTAssertNil(viewModel.errorMessage)
    }

    /// 只念文案，不自己算「还差几分钟」—— 后端没下发最早可开始时刻（后端 #307 ②）。
    func testTooEarlySpeaksTheMappedCopyAndKeepsTheButton() async {
        let service = makeOrderService(reloadStatus: .driverArrived)
        service.startServiceResult = .failure(APIError.serverError(
            ErrorResponse(code: "SERVICE_START_TOO_EARLY", message: "最早 10月6日 09:45 可以操作")
        ))
        let speech = SpeechService()
        let (viewModel, appState) = makeViewModel(service: service, status: .driverArrived, speech: speech)
        _ = appState

        await viewModel.startRun()

        let expected = ErrorCode.serviceStartTooEarly.localizedMessage
        XCTAssertEqual(viewModel.errorMessage, expected)
        XCTAssertEqual(speech.lastSpokenText, expected)
        XCTAssertEqual(viewModel.order?.status, .driverArrived)
        XCTAssertFalse(viewModel.isPerformingAction)
    }

    /// 本地状态过期（例如陪跑员刚取消、订单已转 `REMATCHING`）：刷新，不重试。
    func testStatusRejectionRefreshesTheOrder() async {
        let service = makeOrderService(reloadStatus: .rematching)
        service.startServiceResult = .failure(APIError.serverError(
            ErrorResponse(code: "ORDER_STATUS_NOT_ALLOWED", message: "当前订单状态不允许该操作")
        ))
        let (viewModel, appState) = makeViewModel(service: service, status: .driverArrived)
        _ = appState

        await viewModel.startRun()

        XCTAssertEqual(service.callCount("startService(orderId:)"), 1, "被拒后又重试了")
        XCTAssertEqual(service.callCount("orderDetail(orderId:)"), 1, "被拒后没有刷新订单")
        XCTAssertEqual(viewModel.order?.status, .rematching)
    }

    func testOtherStatusesSendNoRequest() async {
        for status in RunOrderStatus.allCases where status != .driverArrived {
            let service = makeOrderService(reloadStatus: status)
            let (viewModel, appState) = makeViewModel(service: service, status: status)
            _ = appState

            await viewModel.startRun()

            XCTAssertEqual(service.callCount("startService(orderId:)"), 0, "\(status) 不该发开跑请求")
        }
    }

    // MARK: - Mock 与契约对齐

    /// 契约：「调用时订单已是 `IN_PROGRESS`（另一端先按了）→ 两端都返回 200」。
    func testMockAcceptsStartServiceWhenTheOtherSideAlreadyStarted() {
        let mock = MockAPIClient()
        mock.orders = [OrderDetailResponse.preview(orderId: 9001, status: .inProgress)]

        XCTAssertNoThrow(try mock.handleStartService(orderId: 9001))
        XCTAssertEqual(mock.orders.first?.status, .inProgress)
    }

    // MARK: - Fixture

    private func make(
        _ status: RunOrderStatus,
        volunteerPhone: String? = "13800000001"
    ) -> BlindOrderFlowPresentation {
        let order = OrderDetailResponse.preview(
            status: status,
            volunteerName: "张*",
            volunteerTotalCompleted: 32,
            volunteerPhone: volunteerPhone
        )
        guard let presentation = BlindOrderFlowPresentation.make(
            order: order,
            distanceText: nil,
            canKeepWaiting: false
        ) else {
            XCTFail("\(status) 应该落在骨架里")
            return BlindOrderFlowPresentation(
                step: .matching, phase: .beforeRun, visual: .radar, title: "", subtitle: "",
                lastRowTitle: "", primaryAction: nil, warning: nil
            )
        }
        return presentation
    }

    private func makeOrderService(reloadStatus: RunOrderStatus) -> FakeOrderService {
        let service = FakeOrderService()
        service.startServiceResult = .success(())
        service.orderDetailResult = .success(OrderDetailResponse.preview(orderId: 701, status: reloadStatus))
        return service
    }

    /// 返回 `AppState` 让调用方攥着：view model 对它是 `weak`，不攥着出函数即释放
    /// （记忆 `location-service-test-seam-and-weak-viewmodel-deps`）。
    private func makeViewModel(
        service: FakeOrderService,
        status: RunOrderStatus,
        speech: SpeechService = SpeechService()
    ) -> (BlindOrderStatusViewModel, AppState) {
        let appState = AppState(orders: service)
        appState.currentEnvironment = .mock
        let viewModel = BlindOrderStatusViewModel()
        viewModel.configure(appState: appState, speechService: speech)
        viewModel.order = OrderDetailResponse.preview(orderId: 701, status: status)
        return (viewModel, appState)
    }
}
