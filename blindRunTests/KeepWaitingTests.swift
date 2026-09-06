import XCTest
@testable import blindRun

/// 「继续等待」——订单被自动取消前给盲人的出路。
///
/// 后端在订单长时间无人接单时推 `ORDER_CANCELLATION_WARNING`，正文逐字是
/// 「您的订单即将因长时间无人接单被取消，**点击继续等待可延长**」。这些用例钉的是那句话
/// 响起时屏幕上确实有这个控件，且它打对了端点、失败时不乱打第二次。
@MainActor
final class KeepWaitingTests: XCTestCase {

    // MARK: - 状态判定与端点分派

    /// 穷举所有状态。用 `allCases` 而不是逐个写：后端加状态时这条会连同编译器一起提醒。
    ///
    /// `NO_VOLUNTEER` **不在**可延长之列，这是刻意的：后端 `OrderStatus.java:46` 写着
    /// 「预留终态」，`DispatchService.java:574` 同口径，两个端点都会拒。
    /// 可恢复的窗口在订单走到它**之前**。
    func testKeepWaitingIsOfferedOnlyWhileTheOrderIsStillWaitingForAMatch() {
        let expected: Set<RunOrderStatus> = [.pendingMatch, .rematching]

        for status in RunOrderStatus.allCases {
            XCTAssertEqual(
                status.offersKeepWaiting,
                expected.contains(status),
                "\(status) 的「继续等待」可见性与预期不符"
            )
        }

        XCTAssertFalse(
            RunOrderStatus.noVolunteer.offersKeepWaiting,
            "NO_VOLUNTEER 是终态，两个端点都会拒；在这里开口子等于给一个必定失败的按钮"
        )
    }

    /// 端点按状态分派，且两个端点的前置状态互斥。
    func testEachWaitingStatusMapsToItsOwnEndpoint() {
        XCTAssertEqual(RunOrderStatus.pendingMatch.keepWaitingEndpoint, .keepWaiting)
        XCTAssertEqual(RunOrderStatus.rematching.keepWaitingEndpoint, .keepRematching)

        for status in RunOrderStatus.allCases where !status.offersKeepWaiting {
            XCTAssertNil(status.keepWaitingEndpoint, "\(status) 不该有延长端点")
        }
    }

    /// 完整路径必须是源码里的字面量，否则 `validate-spec-coverage.mjs` 归一成
    /// `/api/orders/{param}/{param}`，这两个端点对契约门禁就彻底隐形了。
    func testEndpointPathsAreFullyQualified() {
        XCTAssertEqual(
            KeepWaitingEndpoint.keepWaiting.path(orderId: 42),
            "/api/orders/42/keep-waiting"
        )
        XCTAssertEqual(
            KeepWaitingEndpoint.keepRematching.path(orderId: 42),
            "/api/orders/42/keep-rematching"
        )
    }

    // MARK: - 请求分派

    func testPendingMatchSendsExactlyOnePutToKeepWaiting() async {
        let orderService = makeOrderService()
        let appState = AppState(orders: orderService)
        appState.currentEnvironment = .mock
        let viewModel = BlindOrderStatusViewModel()
        viewModel.configure(appState: appState, speechService: SpeechService())
        viewModel.order = Self.makeOrder(orderId: 501, status: .pendingMatch)

        await viewModel.keepWaiting()

        XCTAssertEqual(orderService.callCount("keepWaiting(_:orderId:)"), 1)
        XCTAssertEqual(orderService.lastKeepWaitingEndpoint, .keepWaiting)
        XCTAssertEqual(orderService.lastOrderId, 501)
    }

    func testRematchingSendsExactlyOnePutToKeepRematching() async {
        let orderService = makeOrderService()
        let appState = AppState(orders: orderService)
        appState.currentEnvironment = .mock
        let viewModel = BlindOrderStatusViewModel()
        viewModel.configure(appState: appState, speechService: SpeechService())
        viewModel.order = Self.makeOrder(orderId: 502, status: .rematching)

        await viewModel.keepWaiting()

        XCTAssertEqual(orderService.callCount("keepWaiting(_:orderId:)"), 1)
        XCTAssertEqual(orderService.lastKeepWaitingEndpoint, .keepRematching)
        XCTAssertEqual(orderService.lastOrderId, 502)
    }

    /// 其余状态一个请求都不许发。没有端点却发请求，收到的一定是 409，
    /// 而盲人听到的会是一句他无法据以行动的报错。
    func testNonWaitingStatusesSendNoRequestAtAll() async {
        for status in RunOrderStatus.allCases where !status.offersKeepWaiting {
            let orderService = makeOrderService()
            let appState = AppState(orders: orderService)
            appState.currentEnvironment = .mock
            let viewModel = BlindOrderStatusViewModel()
            viewModel.configure(appState: appState, speechService: SpeechService())
            viewModel.order = Self.makeOrder(orderId: 503, status: status)

            await viewModel.keepWaiting()

            XCTAssertTrue(orderService.calls.isEmpty, "\(status) 不该发出延长请求")
        }
    }

    /// **design D3 的防退回门。**
    ///
    /// 409 `ORDER_STATUS_NOT_ALLOWED` 的含义是「你手上的状态已经过期了」，
    /// 该做的是刷新订单，不是换一个 URL 再打一次。两个端点的前置状态互斥，回退重试必然也失败，
    /// 而盲人听不见网络请求 —— 连打两次唯一可见的结果是等待时间翻倍。
    func testStatusRejectionRefreshesTheOrderInsteadOfRetryingTheOtherEndpoint() async {
        let orderService = makeOrderService()
        orderService.keepWaitingResult = .failure(APIError.serverError(
            ErrorResponse(code: "ORDER_STATUS_NOT_ALLOWED", message: "当前订单状态不支持此操作")
        ))
        let appState = AppState(orders: orderService)
        appState.currentEnvironment = .mock
        let viewModel = BlindOrderStatusViewModel()
        viewModel.configure(appState: appState, speechService: SpeechService())
        viewModel.order = Self.makeOrder(orderId: 504, status: .pendingMatch)

        await viewModel.keepWaiting()

        XCTAssertEqual(
            orderService.callCount("keepWaiting(_:orderId:)"),
            1,
            "被拒后又打了第二次延长"
        )
        XCTAssertEqual(
            orderService.lastKeepWaitingEndpoint,
            .keepWaiting,
            "回退去试了另一个端点 —— 两者前置状态互斥，这一次必然也失败"
        )
        // 正确的补救动作：拉一次权威订单详情。
        XCTAssertEqual(
            orderService.callCount("orderDetail(orderId:)"),
            1,
            "被拒后没有刷新订单详情，页面会停在一个已经过期的状态上"
        )
    }

    // MARK: - 上限

    /// 上限到了就把按钮收起来（design D5）。后端在延长次数用尽后也不再推送预警 ——
    /// 客户端留着一个必定失败的按钮就是与后端口径背离。
    func testLimitReachedRemovesTheActionForThisOrder() async {
        let orderService = makeOrderService()
        orderService.keepWaitingResult = .failure(APIError.serverError(
            ErrorResponse(code: "KEEP_WAITING_LIMIT_REACHED", message: "继续等待次数已达上限")
        ))
        let appState = AppState(orders: orderService)
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let viewModel = BlindOrderStatusViewModel()
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.order = Self.makeOrder(orderId: 505, status: .pendingMatch)

        XCTAssertTrue(viewModel.canShowKeepWaiting)

        await viewModel.keepWaiting()

        XCTAssertTrue(viewModel.keepWaitingLimitReached)
        XCTAssertFalse(viewModel.canShowKeepWaiting, "上限已到，按钮还留在页面上")
        // 状态没变，所以「不可见」只能来自上限标记，不能来自状态判定。
        XCTAssertTrue(viewModel.order?.status.offersKeepWaiting == true)
        XCTAssertEqual(speechService.lastSpokenText, KeepWaitingCopy.limitReached)
    }

    /// 上限是**这一单**的属性。换单不清会让新订单一进来就少一个本该有的动作。
    func testLimitFlagIsClearedWhenTheOrderChanges() async {
        let orderService = makeOrderService()
        orderService.keepWaitingResult = .failure(APIError.serverError(
            ErrorResponse(code: "KEEP_WAITING_LIMIT_REACHED", message: "继续等待次数已达上限")
        ))
        let appState = AppState(orders: orderService)
        appState.currentEnvironment = .mock
        let viewModel = BlindOrderStatusViewModel()
        viewModel.configure(appState: appState, speechService: SpeechService())
        viewModel.startPolling(orderId: 506)
        viewModel.stopPolling()
        viewModel.order = Self.makeOrder(orderId: 506, status: .pendingMatch)

        await viewModel.keepWaiting()
        XCTAssertTrue(viewModel.keepWaitingLimitReached)

        viewModel.startPolling(orderId: 507)
        viewModel.stopPolling()

        XCTAssertFalse(viewModel.keepWaitingLimitReached, "换单后上限标记没有清空")
    }

    // MARK: - 文案

    /// **design D6 的防退回门。**
    ///
    /// 延长窗口的长度是后端配置（`app.match.max-keep-waiting-count` 与对应超时值），
    /// 客户端读不到。有人后来把这句「优化」成「已为你延长 10 分钟」，那个数字就是编的 ——
    /// 与 SOS 那条「不得宣称短信已送达」同一类错误：把客户端不知道的事说成已经发生。
    func testSuccessCopyIsProgressiveAndStatesNoConcreteDuration() {
        XCTAssertFalse(
            KeepWaitingCopy.success.contains(where: \.isNumber),
            "成功文案出现了数字：窗口长度是后端配置，客户端读不到，写出来就是假信息"
        )
        for unit in ["分钟", "小时", "秒"] {
            XCTAssertFalse(
                KeepWaitingCopy.success.contains(unit),
                "成功文案承诺了具体时长单位「\(unit)」"
            )
        }
        // 进行时而非完成时：后端 200 只回 {"success": true}，订单状态不变。
        XCTAssertTrue(KeepWaitingCopy.success.contains("正在"))
    }

    func testSuccessSpeaksLocalCopyBecauseTheStatusDoesNotChange() async {
        let orderService = makeOrderService()
        let appState = AppState(orders: orderService)
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let viewModel = BlindOrderStatusViewModel()
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.order = Self.makeOrder(orderId: 508, status: .pendingMatch)

        await viewModel.keepWaiting()

        XCTAssertEqual(speechService.lastSpokenText, KeepWaitingCopy.success)
        XCTAssertNil(viewModel.errorMessage)
        // 延长成功不改状态，页面必须停在原地。
        XCTAssertEqual(viewModel.order?.status, .pendingMatch)
    }

    /// 上限文案要说明**还能做什么**。只说「不能延长」会把盲人留在一个没有下一步的地方。
    func testLimitCopyStatesWhatRemainsPossible() {
        XCTAssertTrue(KeepWaitingCopy.limitReached.contains("上限"))
        XCTAssertTrue(
            KeepWaitingCopy.limitReached.contains("取消"),
            "上限文案没有告诉用户还能取消重下"
        )
        XCTAssertTrue(
            KeepWaitingCopy.limitReached.contains("匹配"),
            "上限文案没有说明系统仍会继续匹配"
        )
    }

    // MARK: - 重复当前状态

    /// 看不见屏幕的人靠「重复当前状态」发现这一页还能做什么。
    func testRepeatStatusMentionsKeepWaitingWhileWaiting() {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let viewModel = BlindOrderStatusViewModel()
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.order = Self.makeOrder(orderId: 509, status: .pendingMatch)

        viewModel.repeatStatus()

        let spoken = speechService.lastSpokenText ?? ""
        XCTAssertTrue(spoken.contains(KeepWaitingCopy.repeatStatusSuffix), "播报里没有提到继续等待")
        // 状态本身仍排在最前面，动作是附加而非替代。
        XCTAssertTrue(spoken.hasPrefix(RunOrderStatus.pendingMatch.blindRunnerAnnouncement))
    }

    func testRepeatStatusDropsKeepWaitingOnceTheLimitIsReached() async {
        let orderService = makeOrderService()
        orderService.keepWaitingResult = .failure(APIError.serverError(
            ErrorResponse(code: "KEEP_WAITING_LIMIT_REACHED", message: "继续等待次数已达上限")
        ))
        let appState = AppState(orders: orderService)
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let viewModel = BlindOrderStatusViewModel()
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.order = Self.makeOrder(orderId: 510, status: .pendingMatch)

        await viewModel.keepWaiting()
        viewModel.repeatStatus()

        XCTAssertFalse(
            (speechService.lastSpokenText ?? "").contains(KeepWaitingCopy.repeatStatusSuffix),
            "上限已到还在播报「可以点继续等待」——念了一个已经不存在的按钮"
        )
    }

    func testRepeatStatusStaysSilentAboutKeepWaitingAfterAMatch() {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let viewModel = BlindOrderStatusViewModel()
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.order = Self.makeOrder(orderId: 511, status: .inProgress)

        viewModel.repeatStatus()

        XCTAssertFalse(
            (speechService.lastSpokenText ?? "").contains(KeepWaitingCopy.repeatStatusSuffix)
        )
    }

    // MARK: - Fixture

    private static func makeOrder(orderId: Int64, status: RunOrderStatus) -> OrderDetailResponse {
        OrderDetailResponse(
            orderId: orderId,
            status: status,
            startAddress: "测试出发点",
            startLatitude: nil,
            startLongitude: nil,
            endAddress: nil,
            endLatitude: nil,
            endLongitude: nil,
            plannedStart: nil,
            plannedEnd: nil,
            blindName: nil,
            blindPhone: nil,
            volunteerPhone: nil,
            acceptedAt: nil,
            createdAt: nil,
            expectedDurationMinutes: nil,
            pacePreference: nil,
            routePreference: nil,
            routeNotes: nil,
            hasGuideDogThisRun: nil,
            specialNotes: nil,
            visionLevel: nil,
            tetherPreference: nil,
            chatPreference: nil
        )
    }
}

// MARK: - Fixture

private extension KeepWaitingTests {
    /// 罐装成功值一次配齐。**默认全成功**，要演失败的用例自己覆盖那一条 ——
    /// `FakeOrderService` 的默认是 `NotStubbed`，不配就会红在「你没打这个桩」上。
    ///
    /// 取代了原来的 `KeepWaitingAPIClientStub`：那个桩按路径后缀分派
    /// （`path.hasSuffix("/keep-waiting")`），而路径归属已经由
    /// `OrderEndpointTests` 与 `testEndpointPathsAreFullyQualified` 各自钉住了。
    func makeOrderService() -> FakeOrderService {
        let service = FakeOrderService()
        service.keepWaitingResult = .success(())
        service.orderDetailResult = .success(Self.makeOrder(orderId: 504, status: .pendingMatch))
        return service
    }
}
