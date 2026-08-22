import XCTest
@testable import blindRun

/// 接单前通话磨合（后端迁移 `0031`）。
///
/// 这一族用例钉的不是「功能有没有做」，而是这个功能**做错了就没有意义**的那几条：
/// 号码单向、拒绝无声、拨号入口不念号码、两阶段的冗余退路。
@MainActor
final class IntroCallTests: XCTestCase {

    // MARK: - 状态语义

    /// 四条穷举 switch 的取值。用 `allCases` 遍历而不是逐条断言，
    /// 后端往状态机加值时这里会连同编译器一起提醒。
    func testPendingIntroCallSitsBeforeAcceptanceOnEveryGate() {
        let status = RunOrderStatus.pendingIntroCall

        // 通话发生在接单**之前**，而派单是串行的：展示自由文本等于交给这一单碰到的每个候选人。
        XCTAssertFalse(status.disclosesBlindRunnerNotesToVolunteer)
        // 那条控制的是**双向**下发号码的老路径；本流程走单向专用接口，不许混用。
        XCTAssertFalse(status.offersVolunteerCall)
        XCTAssertFalse(status.isTerminal)
        XCTAssertEqual(status.blindRunnerRoute, .tracking)
        XCTAssertTrue(status.shouldPoll)

        // 后端 `OrderLifecycleService.cancelOrder` 的盲人分支明写着这一态可取消 ——
        // 漏掉会把人困在通话态直到窗口超时。
        XCTAssertTrue(status.canBlindRunnerCancel)
        XCTAssertFalse(status.canVolunteerCancel)

        // 两条延长端点的前置状态是 PENDING_MATCH / REMATCHING，通话态打过去必定 409。
        XCTAssertFalse(status.offersKeepWaiting)
        XCTAssertNil(status.keepWaitingEndpoint)

        // 还没有志愿者接单，后端不下发候选人位置。
        XCTAssertFalse(status.offersVolunteerDistanceToStart)
    }

    /// `.unknown` 不在 `allCases` 里，新状态必须真的进去 ——
    /// 漏掉会让状态机遍历（`canReach`）永远到不了它。
    func testPendingIntroCallIsPartOfTheStateMachineEnumeration() {
        XCTAssertTrue(RunOrderStatus.allCases.contains(.pendingIntroCall))
        XCTAssertEqual(RunOrderStatus.pendingIntroCall.rawValue, "PENDING_INTRO_CALL")
    }

    /// 解码。老版本 App 收到这个值会落 `.unknown`（不崩），新版本必须认出来。
    func testBackendRawValueDecodesIntoTheRealCaseNotUnknown() throws {
        struct Wrapper: Decodable { let status: RunOrderStatus }
        let decoded = try JSONDecoder().decode(
            Wrapper.self,
            from: Data(#"{"status":"PENDING_INTRO_CALL"}"#.utf8)
        )
        XCTAssertEqual(decoded.status, .pendingIntroCall)
    }

    /// 后端 `OrderStatus.java` 的通话磨合分支，逐条对撞。
    ///
    /// 漏一条的后果是实时状态推送被判成 `rejectedInvalid` 直接丢掉 ——
    /// 盲人的页面就永远停在上一个状态，而 App 看起来一切正常。
    func testRealtimeReconcilerAcceptsEveryIntroCallTransition() {
        let cases: [(RunOrderStatus, RunOrderStatus)] = [
            (.pendingMatch, .pendingIntroCall),
            // REMATCHING 在后端 `isDispatchable()` 下与 PENDING_MATCH 行为一致。
            (.rematching, .pendingIntroCall),
            (.pendingIntroCall, .pendingAccept),
            // ⚠️ 退回的是 PENDING_MATCH 而**不是** REMATCHING —— 通话没成时从来没有志愿者接过单。
            (.pendingIntroCall, .pendingMatch),
            (.pendingIntroCall, .cancelled),
            (.pendingIntroCall, .noVolunteer)
        ]

        for (from, to) in cases {
            var reconciler = OrderStatusReconciler()
            reconciler.register(orderID: 1, status: from)
            let result = reconciler.reconcileRealtime(orderID: 1, fromStatus: from, toStatus: to)
            XCTAssertEqual(result, .applied(to), "\(from) → \(to) 被状态机拒了")
        }
    }

    /// 本轮没聊成退回 `PENDING_MATCH` 时，REST 轮询的结果**不能**被当成陈旧丢掉。
    ///
    /// `lifecycleRank` 判「候选状态是不是倒退」，而这一条倒退是真的。
    /// 给通话态排更高的档，盲人的页面就永远停在「等待通话确认」。
    func testFallingBackToMatchingIsNotRejectedAsStale() {
        var reconciler = OrderStatusReconciler()
        reconciler.register(orderID: 7, status: .pendingIntroCall)
        let token = reconciler.requestToken(orderID: 7)

        let result = reconciler.reconcileREST(orderID: 7, candidate: .pendingMatch, token: token)

        XCTAssertEqual(result, .applied(.pendingMatch))
    }

    // MARK: - 号码单向

    /// 🚨 **本仓库 2026-08-11 报过的真实缺陷的回归。**
    ///
    /// 掩码串 `138****1234` 被 `EmergencyDialer.telURL` 取数字位后变成 `1381234`，
    /// 拨出去是空号，而界面上看不出任何异常。所以拨号入口只认 `dialableCounterpartPhone`，
    /// 而志愿者侧那个字段恒为 nil。
    func testVolunteerSideViewHasNothingDialable() {
        let volunteerSide = IntroCallView(
            counterpartName: "王*",
            counterpartPhone: nil,
            counterpartPhoneMasked: "138****1234",
            myDecision: nil,
            windowEndsAt: nil
        )

        XCTAssertNil(volunteerSide.dialableCounterpartPhone)

        // 这一行是上面那条断言存在的全部理由：掩码串**拼得出**一个合法但错误的 tel URL。
        // 类型上拦不住（两个字段都是 String?），只能靠「拨号入口只读另一个字段」。
        XCTAssertEqual(
            EmergencyDialer.telURL(for: volunteerSide.counterpartPhoneMasked)?.absoluteString,
            "tel://1381234"
        )
    }

    func testBlindSideViewDialsThePlainNumber() {
        let blindSide = IntroCallView(
            counterpartName: "李*",
            counterpartPhone: "13800000002",
            counterpartPhoneMasked: nil,
            myDecision: nil,
            windowEndsAt: nil
        )

        XCTAssertEqual(blindSide.dialableCounterpartPhone, "13800000002")
    }

    /// `myDecision` 是开放枚举（契约 `anyOf: [enum, string]`）。后端加值时不许把整条响应带崩，
    /// 也不许被当成「我已经表过态」。
    func testUnknownDecisionValueDegradesInsteadOfCrashing() throws {
        let decoded = try JSONDecoder().decode(
            IntroCallView.self,
            from: Data(#"{"myDecision":"MAYBE_LATER"}"#.utf8)
        )

        XCTAssertNil(decoded.myDecisionValue)
        XCTAssertFalse(decoded.isWaitingForCounterpart)
    }

    // MARK: - 无声拒绝

    /// 🚨 盲人这一侧的每一句文案都不许暗示「前面有人拒绝过你」。
    ///
    /// 依据是 CHI'24 *Help Supporters*（N=20）：平台方案降低视障者求助心理成本的机制，
    /// 正是明眼人可以 silently decline。一旦让盲人听到「第 3 位志愿者拒绝了你」，
    /// 这个功能就从降低心理成本变成制造挫败 —— 正好是它想消除的东西。
    func testBlindFacingCopyNeverLeaksRoundsOrRejection() {
        let forbidden = ["拒绝", "第", "重新", "换了", "又", "没成", "失败"]
        let copy = [
            RunOrderStatus.pendingIntroCall.displayName,
            RunOrderStatus.pendingIntroCall.blindRunnerDescription,
            RunOrderStatus.pendingIntroCall.blindRunnerAnnouncement,
            SpeechService.statusAnnouncement(for: .pendingIntroCall),
            IntroCallCopy.continuedSearch,
            IntroCallCopy.waitingForCounterpart
        ]

        for line in copy {
            for word in forbidden {
                XCTAssertFalse(line.contains(word), "「\(line)」里出现了 \(word)，会暴露轮次或归因")
            }
        }
    }

    /// 「换一位」是盲人自己的退出，不是对他人的否定 —— 措辞里不许有「拒绝」。
    func testDeclineButtonIsFramedAsSwitchingNotRejecting() {
        XCTAssertEqual(IntroCallCopy.declineButtonTitle, "换一位")
        XCTAssertFalse(IntroCallCopy.declineAccessibilityHint.contains("拒绝"))
    }

    /// 🚨 拨号按钮的 hint **不许念号码**。
    ///
    /// 视障跑者在户外常常不戴耳机（要听车流），VoiceOver 外放等于把志愿者的手机号
    /// 广播给周围的人。号码对「要不要打这通电话」这个决策没有帮助。
    func testDialHintNeverContainsDigits() {
        XCTAssertFalse(IntroCallCopy.callAccessibilityHint.contains(where: \.isNumber))
        XCTAssertTrue(IntroCallCopy.callAccessibilityHint.contains("拨号确认"))
    }

    // MARK: - 端点

    /// 完整路径必须是源码里的字面量，否则 `validate-spec-coverage.mjs` 会把它归一成
    /// `/api/orders/{param}/{param}`，这四条端点对契约门禁就彻底隐形了。
    func testEndpointPathsAreFullyQualified() {
        XCTAssertEqual(IntroCallEndpoint.view.path(orderId: 42), "/api/orders/42/intro-call")
        XCTAssertEqual(
            IntroCallEndpoint.decision.path(orderId: 42),
            "/api/orders/42/intro-call/decision"
        )
        XCTAssertEqual(
            IntroCallEndpoint.unreachable.path(orderId: 42),
            "/api/orders/42/intro-call/unreachable"
        )
        XCTAssertEqual(
            IntroCallEndpoint.notifyIncoming.path(orderId: 42),
            "/api/orders/42/intro-call/notify-incoming"
        )
    }

    /// 两个后端错误码都要有确切文案，不能被念成「未知错误 (409)」。
    func testIntroCallErrorCodesMapToActionableCopy() {
        XCTAssertEqual(ErrorCode(rawValue: "INTRO_CALL_NOT_ACTIVE"), .introCallNotActive)
        XCTAssertEqual(ErrorCode.introCallNotActive.localizedMessage, IntroCallCopy.roundAlreadyEnded)
        XCTAssertEqual(ErrorCode(rawValue: "INTRO_CALL_REQUIRED"), .introCallRequired)
        XCTAssertTrue(ErrorCode.introCallRequired.localizedMessage.contains("先"))
    }

    // MARK: - 盲人侧动作

    /// 🚨 **先通知、立刻拨、不等响应。**
    ///
    /// 对盲人来说「点了没反应」是最糟的反馈：等一次网络往返（最坏 15 秒超时）才弹拨号框，
    /// 用户会以为按钮坏了。所以 `introCallDialURL` 是同步返回的，通知那条请求丢进 Task 里跑。
    func testDialingReturnsImmediatelyAndNotifiesTheCounterpartOutOfBand() async {
        let client = IntroCallAPIClientStub()
        client.introCall = Self.blindSideView
        let appState = AppState(apiClient: client)
        appState.currentEnvironment = .mock
        let viewModel = BlindOrderStatusViewModel()
        viewModel.configure(appState: appState, speechService: SpeechService())
        viewModel.order = Self.makeOrder(orderId: 601, status: .pendingIntroCall)
        await viewModel.loadIntroCallForTesting()

        // 同步返回：这一行没有 await，拿到的必须已经是可拨的 URL。
        let url = viewModel.introCallDialURL()

        XCTAssertEqual(url?.absoluteString, "tel://13800000002")

        let didNotify = await Self.waitUntil {
            client.paths.contains("/api/orders/601/intro-call/notify-incoming")
        }
        XCTAssertTrue(didNotify, "拨号前没有通知志愿者，陌生号码来电很可能被当骚扰挂掉")
    }

    /// 拿不到号码时**不返回 URL**。
    ///
    /// 志愿者侧的响应形状（明文为 null）如果误喂到盲人这条路径上，
    /// 唯一正确的结果是「拨不出去」而不是「拨了个空号」。
    func testDialingIsRefusedWhenOnlyAMaskedNumberIsAvailable() async {
        let client = IntroCallAPIClientStub()
        client.introCall = Self.volunteerSideView
        let appState = AppState(apiClient: client)
        appState.currentEnvironment = .mock
        let viewModel = BlindOrderStatusViewModel()
        viewModel.configure(appState: appState, speechService: SpeechService())
        viewModel.order = Self.makeOrder(orderId: 602, status: .pendingIntroCall)
        await viewModel.loadIntroCallForTesting()

        XCTAssertNil(viewModel.introCallDialURL())
        XCTAssertFalse(client.paths.contains("/api/orders/602/intro-call/notify-incoming"))
    }

    /// 🚩 **盲人侧只有两个结果动作，「没打通」不在其中。**
    ///
    /// 对他来说「聊完不合适」和「没打通」结果完全一样（换一位），分成两个按钮只是多一次
    /// 读屏滑动。后端确实要区分（timeout vs declined 直接进 `acceptanceRate`），
    /// 但那个口径由志愿者侧提供。这条用例守的是「别哪天顺手给盲人也加一个」。
    func testBlindRunnerNeverHitsTheVolunteerOnlyUnreachableEndpoint() async {
        for decision in [IntroCallDecision.accept, .decline] {
            let client = IntroCallAPIClientStub()
            client.order = Self.makeOrder(orderId: 603, status: .pendingMatch)
            let appState = AppState(apiClient: client)
            appState.currentEnvironment = .mock
            let viewModel = BlindOrderStatusViewModel()
            viewModel.configure(appState: appState, speechService: SpeechService())
            viewModel.order = Self.makeOrder(orderId: 603, status: .pendingIntroCall)

            await viewModel.submitIntroCallDecision(decision)

            XCTAssertTrue(client.paths.contains("/api/orders/603/intro-call/decision"))
            XCTAssertFalse(
                client.paths.contains { $0.hasSuffix("/intro-call/unreachable") },
                "盲人侧打到了只属于志愿者的端点"
            )
        }
    }

    /// 表态之后**不在本地假设结论**：我说合适 ≠ 成单，那取决于对方，而我们拿不到对方的表态。
    func testAcceptingDoesNotFakeALocalStatusAdvance() async {
        let client = IntroCallAPIClientStub()
        client.order = Self.makeOrder(orderId: 604, status: .pendingIntroCall)
        let appState = AppState(apiClient: client)
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let viewModel = BlindOrderStatusViewModel()
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.order = Self.makeOrder(orderId: 604, status: .pendingIntroCall)

        await viewModel.submitIntroCallDecision(.accept)

        XCTAssertEqual(viewModel.order?.status, .pendingIntroCall)
        XCTAssertEqual(speechService.lastSpokenText, IntroCallCopy.waitingForCounterpart)
    }

    // MARK: - 退回派单队列的播报

    /// 🚨 通话没聊成退回 `PENDING_MATCH` 时，**不能**播 `.pendingMatch` 的常规文案
    /// 「订单提交成功，系统正在为你派单」—— 订单是二十分钟前提交的，这句话在这一刻是错的。
    ///
    /// 后端为这条转移专门发了 `INTRO_CALL_CONTINUE`（正文「正在为你寻找合适的陪跑伙伴」），
    /// 客户端逐字复用它，且与常规等待**读起来完全一样**。
    func testFallingBackToMatchingSpeaksTheNeutralContinuationCopy() async {
        let client = IntroCallAPIClientStub()
        client.order = Self.makeOrder(orderId: 605, status: .pendingMatch)
        let appState = AppState(apiClient: client)
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let viewModel = BlindOrderStatusViewModel()
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.order = Self.makeOrder(orderId: 605, status: .pendingIntroCall)

        viewModel.startPolling(orderId: 605)
        let didFallBack = await Self.waitUntil { viewModel.order?.status == .pendingMatch }
        viewModel.stopPolling()

        XCTAssertTrue(didFallBack)
        XCTAssertEqual(speechService.lastSpokenText, IntroCallCopy.continuedSearch)
        XCTAssertNotEqual(
            speechService.lastSpokenText,
            RunOrderStatus.pendingMatch.blindRunnerAnnouncement,
            "播成了「订单提交成功」——订单二十分钟前就提交了"
        )
        XCTAssertNil(viewModel.introCall, "离开通话态之后号码还留在内存里")
    }

    // MARK: - 志愿者侧

    /// 志愿者侧一次给全三个动作，其中「一直没接到电话」走的是**另一个端点**。
    ///
    /// 与 `DECLINE` 合并会错误拉低这位志愿者的 `acceptanceRate` —— 他并没有拒绝任何人，
    /// 而那个数字直接进派单评分。
    func testVolunteerUnreachableUsesItsOwnEndpointNotDecline() async {
        let client = IntroCallAPIClientStub()
        let appState = AppState(apiClient: client)
        appState.currentEnvironment = .mock
        let viewModel = VolunteerIntroCallViewModel()
        viewModel.configure(orderId: 606, appState: appState, speechService: SpeechService())

        await viewModel.reportUnreachable()

        XCTAssertTrue(client.paths.contains("/api/orders/606/intro-call/unreachable"))
        XCTAssertFalse(client.paths.contains { $0.hasSuffix("/intro-call/decision") })
    }

    /// 本轮结束后「这一单是不是我的」**只能**靠订单详情读不读得到来判 ——
    /// 通话端点刻意不回对方的表态，这是这个契约下唯一存在的判据。
    func testVolunteerResolvesTheRoundByWhetherOrderDetailBecameReadable() async {
        // 成了：后端 `confirmMatch` 写上 `order.volunteer`，订单详情从此读得到。
        let matched = IntroCallAPIClientStub()
        matched.introCallError = APIError.serverError(
            ErrorResponse(code: "INTRO_CALL_NOT_ACTIVE", message: "这一轮通话已经结束了")
        )
        matched.order = Self.makeOrder(orderId: 607, status: .pendingAccept)
        let matchedState = AppState(apiClient: matched)
        matchedState.currentEnvironment = .mock
        let matchedViewModel = VolunteerIntroCallViewModel()
        matchedViewModel.configure(orderId: 607, appState: matchedState, speechService: SpeechService())

        matchedViewModel.startPolling()
        let didMatch = await Self.waitUntil { matchedViewModel.outcome == .matched }
        matchedViewModel.stopPolling()
        XCTAssertTrue(didMatch)
        XCTAssertEqual(matchedViewModel.matchedOrder?.orderId, 607)

        // 没成：`order.volunteer` 仍是 null，订单详情继续 403。
        let closed = IntroCallAPIClientStub()
        closed.introCallError = APIError.serverError(
            ErrorResponse(code: "INTRO_CALL_NOT_ACTIVE", message: "这一轮通话已经结束了")
        )
        closed.order = nil
        let closedState = AppState(apiClient: closed)
        closedState.currentEnvironment = .mock
        let closedViewModel = VolunteerIntroCallViewModel()
        closedViewModel.configure(orderId: 608, appState: closedState, speechService: SpeechService())

        closedViewModel.startPolling()
        let didClose = await Self.waitUntil { closedViewModel.outcome == .closed }
        closedViewModel.stopPolling()
        XCTAssertTrue(didClose)
        XCTAssertNil(closedViewModel.matchedOrder)
    }

    /// 志愿者侧的结束文案同样中性、不归因 —— 他也不该被告知「跑者拒绝了你」。
    func testVolunteerClosingCopyDoesNotAttributeTheOutcome() {
        for word in ["拒绝", "不合适", "没选你", "失败"] {
            XCTAssertFalse(IntroCallCopy.volunteerRoundClosed.contains(word))
        }
    }

    // MARK: - 志愿者接单前只看得到导盲犬

    /// 通话页复用 `VolunteerRunnerNeedsBanner`，内容来自派单载荷。
    ///
    /// 派单载荷刻意只带取值空间封闭的字段，`visionLevel` / `tetherPreference` 一个都没有 ——
    /// 这不是漏了，是 `AGENTS.md §8` 的接单前隐私边界。
    func testDispatchPayloadOnlyEverYieldsTheGuideDogRow() {
        XCTAssertEqual(Self.makeDispatchOrder(hasGuideDog: true).escortNeeds.map(\.kind), [.guideDog])
        XCTAssertTrue(Self.makeDispatchOrder(hasGuideDog: false).escortNeeds.isEmpty)
        XCTAssertTrue(Self.makeDispatchOrder(hasGuideDog: nil).escortNeeds.isEmpty)
    }

    /// 订单详情那条路在通话态同样只剩导盲犬 —— 闸关着，健康信息一个字都不出去。
    func testOrderDetailDuringIntroCallHidesHealthFields() {
        var order = Self.makeOrder(orderId: 609, status: .pendingIntroCall)
        order = OrderDetailResponse(
            orderId: order.orderId,
            status: .pendingIntroCall,
            startAddress: order.startAddress,
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
            routeNotes: "沿湖边跑道",
            hasGuideDogThisRun: true,
            specialNotes: "我有低血糖，说头晕请马上停下",
            visionLevel: "TOTAL_BLIND",
            tetherPreference: "TETHER_ROPE",
            chatPreference: nil
        )

        XCTAssertEqual(order.escortNeeds.map(\.kind), [.guideDog])
    }

    // MARK: - Fixtures

    private static let blindSideView = IntroCallView(
        counterpartName: "李*",
        counterpartPhone: "13800000002",
        counterpartPhoneMasked: nil,
        myDecision: nil,
        windowEndsAt: nil
    )

    private static let volunteerSideView = IntroCallView(
        counterpartName: "王*",
        counterpartPhone: nil,
        counterpartPhoneMasked: "138****1234",
        myDecision: nil,
        windowEndsAt: nil
    )

    private static func makeDispatchOrder(hasGuideDog: Bool?) -> WSNewOrder {
        WSNewOrder(
            type: "NEW_ORDER",
            timestamp: nil,
            orderId: 1,
            startAddress: "朝阳公园南门",
            startLatitude: nil,
            startLongitude: nil,
            distanceKm: 2.5,
            plannedStart: nil,
            plannedEnd: nil,
            dispatchTimeoutSeconds: 30,
            priority: "HIGH",
            pacePreference: nil,
            hasGuideDog: hasGuideDog
        )
    }

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

    private static func waitUntil(
        timeout: TimeInterval = 2,
        _ condition: @MainActor () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }
}

// MARK: - Stub

/// 记录**每一条**请求路径。这一族用例里最要紧的几条断言都是「有没有打到那个端点」——
/// 「盲人打了志愿者专属端点」「拨号前没通知对方」都只有靠完整的请求序列才看得出来。
private final class IntroCallAPIClientStub: APIClientProtocol, @unchecked Sendable {
    enum StubError: Error { case unexpectedType, notFound }

    private(set) var paths: [String] = []
    var introCall: IntroCallView?
    var introCallError: APIError?
    /// `nil` = 订单详情读不到（后端在通话期对志愿者就是 403）。
    var order: OrderDetailResponse?

    func request<T: Decodable>(
        method: HTTPMethod,
        path: String,
        query: [String: String]?,
        body: (any Encodable & Sendable)?,
        requiresAuth: Bool
    ) async throws -> T {
        paths.append(path)

        if path.hasSuffix("/intro-call"), method == .get {
            if let introCallError { throw introCallError }
            guard let value = introCall as? T else { throw StubError.notFound }
            return value
        }
        if path.contains("/intro-call/") {
            guard let value = EmptyResponse() as? T else { throw StubError.unexpectedType }
            return value
        }
        if method == .get, path.hasPrefix("/api/orders/") {
            guard let order, let value = order as? T else { throw StubError.notFound }
            return value
        }
        guard let value = EmptyResponse() as? T else { throw StubError.unexpectedType }
        return value
    }

    func upload<T: Decodable>(
        path: String,
        query: [String: String]?,
        fields: [String: String]?,
        files: [MultipartFile],
        requiresAuth: Bool
    ) async throws -> T {
        throw StubError.unexpectedType
    }
}
