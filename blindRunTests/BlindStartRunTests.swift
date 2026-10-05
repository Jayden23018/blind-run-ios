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

    // MARK: - 到点才亮（后端 #546 的 earliestServiceStartAt）

    /// 还没到最早可开始时刻：同一个按钮、不可按，副标题与读屏提示说出几点可以按。
    /// 用两个时刻分别落在 `now` 两侧来测 —— 只测一侧分不出「判据写反了」与「根本没判」。
    func testStartRunIsLockedUntilTheServerGivenTimeAndSaysWhen() throws {
        let now = Date()
        let opens = now.addingTimeInterval(20 * 60)
        var order = OrderDetailResponse.preview(status: .driverArrived, volunteerName: "张*", volunteerPhone: "13800000001")
        order.earliestServiceStartAt = DateFormatter.aidRunBackendLocalDateTime.string(from: opens)
        let clock = DateFormatter.aidRunDisplayClock.string(from: try XCTUnwrap(order.earliestServiceStartAt?.backendTimestamp))

        let locked = try XCTUnwrap(BlindOrderFlowPresentation.make(order: order, distanceText: nil, canKeepWaiting: false, now: now))
        XCTAssertEqual(locked.primaryAction, .startRunLocked(opensAt: clock))
        XCTAssertEqual(locked.primaryAction?.title, "开始跑步", "锁住时按钮名不变，位置不变")
        XCTAssertEqual(locked.primaryAction?.isEnabled, false)
        XCTAssertTrue(locked.subtitle.contains("\(clock) 起可以开始跑步"), "实际：\(locked.subtitle)")

        let open = try XCTUnwrap(BlindOrderFlowPresentation.make(
            order: order, distanceText: nil, canKeepWaiting: false, now: opens.addingTimeInterval(1)
        ))
        XCTAssertEqual(open.primaryAction, .startRun, "到点之后没有亮起来")
        XCTAssertTrue(open.subtitle.contains(BlindRunCopy.metUpSubtitle))
    }

    /// 字段没下发时不锁：由后端判，按下去最多听到一句「还没到时间」。锁住而后端其实放行，才是更糟的那种。
    func testStartRunIsNotLockedWhenTheServerGivesNoTime() {
        let order = OrderDetailResponse.preview(status: .driverArrived, volunteerName: "张*", volunteerPhone: "13800000001")
        XCTAssertNil(order.earliestServiceStartAt)
        XCTAssertEqual(
            BlindOrderFlowPresentation.make(order: order, distanceText: nil, canKeepWaiting: false)?.primaryAction,
            .startRun
        )
    }

    /// 状态推送换状态时这个字段要带过去，否则推送与重拉之间那几秒按钮会闪成可按。
    func testReplacingStatusKeepsTheEarliestStartTime() {
        var order = OrderDetailResponse.preview(status: .driverEnRoute)
        order.earliestServiceStartAt = "2026-10-06T09:45:00"
        XCTAssertEqual(order.replacingStatus(with: .driverArrived).earliestServiceStartAt, "2026-10-06T09:45:00")
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
    func testTooEarlySpeaksTheMappedCopyAndKeepsTheButton() async throws {
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
        XCTAssertFalse(viewModel.isStartingRun, "失败之后按钮没有恢复成可按")
        let order = try XCTUnwrap(viewModel.order)
        XCTAssertEqual(
            BlindOrderFlowPresentation.make(
                order: order, distanceText: nil, canKeepWaiting: false,
                isStartingRun: viewModel.isStartingRun
            )?.primaryAction,
            .startRun,
            "太早被拒之后主按钮必须还是「开始跑步」，到点后还要再按"
        )
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
        // `loadOrder` 第一步会清空 `errorMessage`，所以错误要在重拉之后设，否则屏幕上一闪就没了。
        XCTAssertNotNil(viewModel.errorMessage, "被拒的原因刚显示就被重拉清掉了")
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

    /// 按下那一刻先念一句：成功之前可能要等网络，读屏焦点停在按钮上时按钮文字变了不会自动重读。
    func testPressingStartSpeaksImmediatelyBeforeTheServerAnswers() async {
        let service = makeOrderService(reloadStatus: .inProgress)
        let speech = SpeechService()
        let (viewModel, appState) = makeViewModel(service: service, status: .driverArrived, speech: speech)
        _ = appState

        await viewModel.startRun()

        XCTAssertEqual(speech.spokenHistoryForTesting.first, BlindRunCopy.startingAnnouncement)
        XCTAssertFalse(viewModel.isStartingRun)
    }

    /// 请求在途时主按钮原位换成不可点的「准备中」—— 不然慢网络下再按会被静默吞掉。
    func testPrimaryActionIsDisabledWhileTheStartRequestIsInFlight() {
        let order = OrderDetailResponse.preview(status: .driverArrived, volunteerName: "张*", volunteerPhone: "13800000001")
        let presentation = BlindOrderFlowPresentation.make(
            order: order, distanceText: nil, canKeepWaiting: false, isStartingRun: true
        )
        XCTAssertEqual(presentation?.primaryAction, .preparing)
        XCTAssertEqual(presentation?.primaryAction?.isEnabled, false)
    }

    /// 主按钮不再是打电话，但打电话没有消失：汇合态的「遇到问题」打开求助中心，
    /// 号码可拨时那里有「直接拨给陪跑员」。
    func testCallingTheVolunteerStaysReachableFromTheSafetyHub() {
        XCTAssertEqual(make(.driverArrived).lastRowTitle, "遇到问题")
        XCTAssertTrue(
            BlindActiveRunSafetyHubOption.tiles(volunteerPhone: "13800000001", primaryContact: nil)
                .contains(.contactVolunteer)
        )
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
