import CoreLocation
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
            // 退出通话回的是「**进通话之前那个状态**」（后端 2026-08-26 修 N105 时改的，
            // 此前写死 PENDING_MATCH）。所以两个落点都要认。
            (.pendingIntroCall, .pendingMatch),
            (.pendingIntroCall, .rematching),
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
            windowEndsAt: nil,
            startAddress: nil,
            plannedStartTime: nil,
            plannedEndTime: nil
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
            windowEndsAt: nil,
            startAddress: nil,
            plannedStartTime: nil,
            plannedEndTime: nil
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
        await viewModel.reloadIntroCall()

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
        await viewModel.reloadIntroCall()

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
        let safety = FakeSafetyService()
        safety.introCallResult = .success(Self.volunteerSideView)
        let appState = AppState(safety: safety)
        let viewModel = VolunteerIntroCallViewModel()
        viewModel.configure(orderId: 606, appState: appState, speechService: SpeechService())

        await viewModel.reportUnreachable()

        // 两条端点分别对应 service 上的两个方法（路径映射由 `SafetyServiceTests` 守），
        // 所以「走的是不是另一条」在这里就是「调的是不是另一个方法」。
        XCTAssertTrue(safety.calls.contains("reportIntroCallUnreachable(orderId:)"))
        XCTAssertFalse(safety.calls.contains("submitIntroCallDecision(orderId:decision:)"))
        XCTAssertEqual(safety.lastOrderId, 606)
    }

    /// 本轮结束后「这一单是不是我的」**只能**靠订单详情读不读得到来判 ——
    /// 通话端点刻意不回对方的表态，这是这个契约下唯一存在的判据。
    func testVolunteerResolvesTheRoundByWhetherOrderDetailBecameReadable() async {
        // 成了：后端 `confirmMatch` 写上 `order.volunteer`，订单详情从此读得到。
        let matched = FakeSafetyService()
        matched.introCallResult = .failure(
            APIError.serverError(ErrorResponse(code: "INTRO_CALL_NOT_ACTIVE", message: "这一轮通话已经结束了"))
        )
        matched.matchedOrderResult = .success(Self.makeOrder(orderId: 607, status: .pendingAccept))
        let matchedState = AppState(safety: matched)
        let matchedViewModel = VolunteerIntroCallViewModel()
        matchedViewModel.configure(orderId: 607, appState: matchedState, speechService: SpeechService())

        matchedViewModel.startPolling()
        let didMatch = await Self.waitUntil { matchedViewModel.outcome == .matched }
        matchedViewModel.stopPolling()
        XCTAssertTrue(didMatch)
        XCTAssertEqual(matchedViewModel.matchedOrder?.orderId, 607)

        // 没成：`order.volunteer` 仍是 null，订单详情继续 403。
        let closed = FakeSafetyService()
        closed.introCallResult = .failure(
            APIError.serverError(ErrorResponse(code: "INTRO_CALL_NOT_ACTIVE", message: "这一轮通话已经结束了"))
        )
        closed.matchedOrderResult = .failure(APIError.unknown(statusCode: 403))
        let closedState = AppState(safety: closed)
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

    // MARK: - 通话数据拉不到时的兜底

    /// 🚨 **这一族用例守的是一个真实的静默失败。**
    ///
    /// 改动前：拉通话数据用 `try?`，失败即 `introCall = nil`，而 `introCallSection` 靠
    /// `let introCall` 拆包 ⇒ 拨号 / 合适 / 换一位三个按钮**一个都不渲染**、没有错误文字、
    /// 没有播报，而状态播报仍在说「有位志愿者想陪你跑，可以打个电话聊聊」。
    /// 盲人被告知去做一件屏幕上根本没有入口的事。
    func testIntroCallLoadFailureIsAnnouncedInsteadOfSilentlyEmptyingTheScreen() async {
        let client = IntroCallAPIClientStub()
        client.introCallError = .unknown(statusCode: 500)
        let appState = AppState(apiClient: client)
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let viewModel = BlindOrderStatusViewModel()
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.order = Self.makeOrder(orderId: 701, status: .pendingIntroCall)

        await viewModel.reloadIntroCall()

        XCTAssertNil(viewModel.introCall, "拉失败还留着数据，会把电话打给上一位候选人")
        XCTAssertTrue(
            viewModel.introCallUnavailable,
            "失败没有留下任何痕迹 —— 界面无从把它和「不在通话态」区分开"
        )
        XCTAssertEqual(speechService.lastSpokenText, IntroCallCopy.loadFailed)
    }

    /// 只在 `false → true` 那一跳播一次。`loadOrder` 每 5 秒重跑一遍，
    /// 每轮都播会把读屏用户淹掉 —— 他要听的是「这次没拿到，可以重试」，
    /// 不是同一句话每 5 秒一遍。
    func testIntroCallLoadFailureIsAnnouncedOnceNotOnEveryPoll() async {
        let client = IntroCallAPIClientStub()
        client.introCallError = .unknown(statusCode: 500)
        let appState = AppState(apiClient: client)
        appState.currentEnvironment = .mock
        let firstRound = SpeechService()
        let viewModel = BlindOrderStatusViewModel()
        viewModel.configure(appState: appState, speechService: firstRound)
        viewModel.order = Self.makeOrder(orderId: 702, status: .pendingIntroCall)

        await viewModel.reloadIntroCall()
        XCTAssertEqual(firstRound.lastSpokenText, IntroCallCopy.loadFailed)

        // ⚠️ 换一个实例来验第二轮，不是 `stop()` 之后复用同一个：`stop()` 只停合成器，
        // `lastSpokenText` 是不清的（`SpeechService.swift:150-154`），复用会让断言恒假地通过。
        let secondRound = SpeechService()
        viewModel.configure(appState: appState, speechService: secondRound)
        await viewModel.reloadIntroCall()

        XCTAssertTrue(viewModel.introCallUnavailable)
        XCTAssertNil(secondRound.lastSpokenText, "第二轮轮询又播了一遍，读屏用户会被同一句话淹掉")
    }

    /// 失败态必须跟着订单状态一起清干净，否则下一单一进通话态就顶着上一单的错误块。
    func testLeavingIntroCallStatusClearsTheFailureState() async {
        let client = IntroCallAPIClientStub()
        client.introCallError = .unknown(statusCode: 500)
        let appState = AppState(apiClient: client)
        appState.currentEnvironment = .mock
        let viewModel = BlindOrderStatusViewModel()
        viewModel.configure(appState: appState, speechService: SpeechService())
        viewModel.order = Self.makeOrder(orderId: 703, status: .pendingIntroCall)
        await viewModel.reloadIntroCall()
        XCTAssertTrue(viewModel.introCallUnavailable)

        viewModel.order = Self.makeOrder(orderId: 703, status: .pendingAccept)
        await viewModel.reloadIntroCall()

        XCTAssertNil(viewModel.introCall)
        XCTAssertFalse(viewModel.introCallUnavailable)
    }

    /// 拉成功之后失败态要翻回去 —— 重试按下之后界面得真的能回到可拨号的样子。
    func testSuccessfulReloadClearsTheFailureState() async {
        let client = IntroCallAPIClientStub()
        client.introCallError = .unknown(statusCode: 500)
        let appState = AppState(apiClient: client)
        appState.currentEnvironment = .mock
        let viewModel = BlindOrderStatusViewModel()
        viewModel.configure(appState: appState, speechService: SpeechService())
        viewModel.order = Self.makeOrder(orderId: 704, status: .pendingIntroCall)
        await viewModel.reloadIntroCall()
        XCTAssertTrue(viewModel.introCallUnavailable)

        client.introCallError = nil
        client.introCall = Self.blindSideView
        await viewModel.reloadIntroCall()

        XCTAssertFalse(viewModel.introCallUnavailable)
        XCTAssertEqual(viewModel.introCallDialURL()?.absoluteString, "tel://13800000002")
    }

    /// 🚨 **表过态之后，「拉不到通话数据」不算失败。**
    ///
    /// 这条是 2026-08-27 真机跑出来的一条真回归的钉子：`submitIntroCallDecision` 成功后
    /// 紧接着 `loadOrder` → 会去拉通话数据，而那一步失败时最初的实现照样报错，
    /// 于是用户刚听完「已经告诉系统你觉得合适」就被「暂时拿不到通话信息」盖掉，
    /// **屏幕上还会冒出一个「换一位」—— 他刚说完合适**。
    ///
    /// 表态服务端已经记下了，拉不到 view 不改变这件事，此刻他也没有任何该做而做不了的事。
    func testFailedRefreshAfterAcceptingIsNotReportedAsAFailure() async {
        let client = IntroCallAPIClientStub()
        // introCall 不设 ⇒ GET /intro-call 抛错，正是表态成功后那一次刷新会走的路。
        client.order = Self.makeOrder(orderId: 705, status: .pendingIntroCall)
        let appState = AppState(apiClient: client)
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let viewModel = BlindOrderStatusViewModel()
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.order = Self.makeOrder(orderId: 705, status: .pendingIntroCall)

        await viewModel.submitIntroCallDecision(.accept)

        XCTAssertEqual(
            speechService.lastSpokenText,
            IntroCallCopy.waitingForCounterpart,
            "表态成功的确认被那次刷新失败盖掉了"
        )
        XCTAssertFalse(viewModel.introCallUnavailable, "表过态之后还把拉不到当成失败")
        XCTAssertTrue(
            viewModel.isWaitingForIntroCallCounterpart,
            "拉不到就不知道自己在等对方了 —— 这件事本地已经知道，不该依赖再拉一次"
        )
    }

    /// 服务端说了话就以它为准：换了候选人时 `myDecision` 回 nil，
    /// 本地那个「我表过态」的记号必须跟着作废 —— 否则新一轮一开局就显示成「正在等对方」，
    /// 而用户其实还没打那通电话。
    func testServerClearsTheLocalDecisionWhenTheRoundMovesToANewCandidate() async {
        let client = IntroCallAPIClientStub()
        client.order = Self.makeOrder(orderId: 706, status: .pendingIntroCall)
        let appState = AppState(apiClient: client)
        appState.currentEnvironment = .mock
        let viewModel = BlindOrderStatusViewModel()
        viewModel.configure(appState: appState, speechService: SpeechService())
        viewModel.order = Self.makeOrder(orderId: 706, status: .pendingIntroCall)

        await viewModel.submitIntroCallDecision(.accept)
        XCTAssertTrue(viewModel.isWaitingForIntroCallCounterpart)

        // 换了候选人：后端这一轮回的 myDecision 是 nil。
        client.introCall = Self.blindSideView
        await viewModel.reloadIntroCall()

        XCTAssertNil(viewModel.submittedIntroCallDecision)
        XCTAssertFalse(
            viewModel.isWaitingForIntroCallCounterpart,
            "新一轮开局就显示成「正在等对方」，而用户还没打那通电话"
        )
    }

    // MARK: - 冷启动恢复（introCallOrderId）

    /// 🚨 后端为这个字段写的理由逐字：通话态 `order.volunteer` 还是 null ⇒
    /// `GET /api/orders/{id}` 恒 403、`/api/orders/mine` 也不返回，而派单推送不会重放 ——
    /// **志愿者杀掉 App 再打开就回不到通话页，只能等 20 分钟窗口超时，而盲人在等他。**
    func testColdStartRecoveryOpensTheIntroCallFromDispatchSummary() {
        let viewModel = VolunteerHomeViewModel()

        viewModel.apply(summary: Self.makeSummary(introCallOrderId: 812))

        XCTAssertEqual(viewModel.pendingIntroCallOrder?.orderId, 812)
        XCTAssertNil(
            viewModel.pendingIntroCallOrder?.dispatchOrder,
            "恢复路径上没有派单载荷，编一个出发地比空着更糟"
        )
    }

    /// 🚨 **这条是那个记号存在的唯一理由。** 没有它：用户手动返回 → `pendingIntroCallOrder` 被清
    /// → 下一次摘要刷新看到 `introCallOrderId` 还在 → 又把他推回通话页，
    /// 在 20 分钟窗口结束前出不来。
    func testColdStartRecoveryDoesNotReopenAfterTheUserBacksOut() {
        let viewModel = VolunteerHomeViewModel()
        let summary = Self.makeSummary(introCallOrderId: 812)

        viewModel.apply(summary: summary)
        XCTAssertNotNil(viewModel.pendingIntroCallOrder)

        viewModel.clearIntroCall()
        viewModel.apply(summary: summary)

        XCTAssertNil(viewModel.pendingIntroCallOrder, "用户返回之后又被拽回通话页了")
    }

    /// 换一单要再跳一次 —— 那是另一个人在等他。记号跟着 orderId 走，不是「跳过就再也不跳」。
    func testColdStartRecoveryOpensAgainForADifferentOrder() {
        let viewModel = VolunteerHomeViewModel()

        viewModel.apply(summary: Self.makeSummary(introCallOrderId: 812))
        viewModel.clearIntroCall()
        viewModel.apply(summary: Self.makeSummary(introCallOrderId: 813))

        XCTAssertEqual(viewModel.pendingIntroCallOrder?.orderId, 813)
    }

    /// 绝大多数时候它是 null，那时一步都不许动导航。
    func testNoIntroCallOrderIdLeavesNavigationAlone() {
        let viewModel = VolunteerHomeViewModel()

        viewModel.apply(summary: Self.makeSummary(introCallOrderId: nil))

        XCTAssertNil(viewModel.pendingIntroCallOrder)
    }

    /// 🚨 **恢复出来的页面不能只有一个号码。**
    ///
    /// 后端为这件事往 `IntroCallView` 加了 `startAddress` / `plannedStartTime`
    /// （字段说明里点名「杀掉 App 再打开就回不到通话页」），而手写模型此前一个都没接 ——
    /// 字段到了被 `Decodable` 静默丢弃。这条走 `JSONDecoder` 验字段名，
    /// 因为构造器测不出「后端叫 startAddress 而我们写成别的」。
    func testIntroCallViewCarriesTheOrderFactsNeededAfterAColdStart() throws {
        let json = """
        {"counterpartName":"王*","counterpartPhoneMasked":"138****1234",
         "startAddress":"朝阳公园南门","startLatitude":39.94,"startLongitude":116.47,
         "plannedStartTime":"2026-08-27T07:30:00","plannedEndTime":"2026-08-27T08:30:00"}
        """
        let decoded = try JSONDecoder().decode(IntroCallView.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.startAddress, "朝阳公园南门")
        XCTAssertEqual(decoded.plannedStartTime, "2026-08-27T07:30:00")
        XCTAssertEqual(decoded.plannedEndTime, "2026-08-27T08:30:00")
        // 志愿者侧仍然只有掩码号 —— 加这三个字段不许把号码那条单向规则捎带松掉。
        XCTAssertNil(decoded.dialableCounterpartPhone)
    }

    /// 时间形状：`IntroCallView.plannedStartTime` 契约上是 `date-time`（可带偏移），
    /// 而派单推送那条 `plannedStart` 是无偏移的 `LocalDateTime`。
    /// 两条路径展示走**同一个** `String.displayDateTime`，所以两种形状都得认得出来 ——
    /// 认不出时它原样返回，界面上就会出现一串 ISO 时间戳。
    func testBothTimestampShapesRenderAsDisplayTimeNotRawISO() {
        for raw in ["2026-08-27T07:30:00", "2026-08-27T07:30:00+08:00", "2026-08-27T07:30:00.123Z"] {
            XCTAssertNotEqual(raw.displayDateTime, raw, "「\(raw)」没被解析，会原样显示成 ISO 串")
        }
    }

    /// 走 `JSONDecoder` 不走构造器：验的是**字段名对不对得上**。
    /// 构造器测不出后端叫 `introCallOrderId` 而我们写成别的 —— 那正是这个字段
    /// 「到了但被静默丢弃」了三天的原因。
    func testDispatchSummaryDecodesIntroCallOrderIdFromTheWire() throws {
        let json = #"{"canDispatch":true,"introCallOrderId":812}"#
        let decoded = try JSONDecoder().decode(
            VolunteerDispatchSummaryResponse.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(decoded.introCallOrderId, 812)
    }

    /// 契约逐字：**它不在 `activeOrders` 里，也不要合并进去** —— 人还没接单，
    /// 那一态 `sharesLiveLocation()` 为 false，混进活跃订单会让位置协同空转。
    func testIntroCallOrderIsNotTreatedAsAnActiveOrder() {
        let viewModel = VolunteerHomeViewModel()

        viewModel.apply(summary: Self.makeSummary(introCallOrderId: 812))

        XCTAssertNil(viewModel.activeOrder, "通话磨合的那一单被当成在途订单了")
    }

    // MARK: - 熟人误发 INTERESTED（INTRO_CALL_NOT_REQUIRED）

    /// 后端 2026-08-26 给「已经磨合成功过的一对又发 `INTERESTED`」加了 409
    /// `INTRO_CALL_NOT_REQUIRED`。**这个码对本 App 是死路**：派单弹窗只有「有意向」和「拒绝」
    /// 两个按钮，界面上没有任何控件能发 `ACCEPT`，只弹一句文案就等于让志愿者卡在一个
    /// 本该能接的单上，而盲人正在等这一轮。
    ///
    /// 所以要自动改发一次 `ACCEPT`。断言看的是**请求序列**：`INTERESTED` → `ACCEPT`。
    func testFamiliarPairFallingIntoIntroCallNotRequiredIsUpgradedToAccept() async {
        let client = DispatchRespondStub()
        client.failNextInterestedWith = .introCallNotRequired
        client.order = Self.makeOrder(orderId: 610, status: .pendingAccept)
        let appState = AppState(apiClient: client)
        appState.currentEnvironment = .mock
        appState.volunteerProfile = Self.dispatchReadyProfile
        let speechService = SpeechService()
        let viewModel = VolunteerHomeViewModel()
        viewModel.configure(with: appState, speechService: speechService)
        viewModel.incomingOrder = Self.makeDispatchOrder(hasGuideDog: nil)

        viewModel.respondToDispatch(
            action: .interested,
            currentLocation: CLLocationCoordinate2D(latitude: 39.9, longitude: 116.4),
            locationAuthorized: true
        )

        let didUpgrade = await Self.waitUntil { client.respondActions.count >= 2 }
        XCTAssertTrue(didUpgrade, "收到 INTRO_CALL_NOT_REQUIRED 之后没有改发 ACCEPT")
        XCTAssertEqual(client.respondActions, ["INTERESTED", "ACCEPT"])
        XCTAssertNil(viewModel.errorMessage, "自动改发成功了却还留着一句错误提示")
        XCTAssertNil(
            viewModel.pendingIntroCallOrder,
            "熟人被升级成直接接单，不该再把他推进通话页"
        )
        XCTAssertEqual(
            speechService.lastSpokenText,
            VolunteerHomeViewModel.dispatchResponseSpeech(for: .accept)
        )
    }

    /// 升级**最多一次**。后端若对 `ACCEPT` 也回同一个码（不该发生，但客户端不能因此打转），
    /// 必须停下来把话说出来，而不是无限重发。
    func testTheUpgradeHappensAtMostOnce() async {
        let client = DispatchRespondStub()
        client.failNextInterestedWith = .introCallNotRequired
        client.failEveryAcceptWith = .introCallNotRequired
        let appState = AppState(apiClient: client)
        appState.currentEnvironment = .mock
        appState.volunteerProfile = Self.dispatchReadyProfile
        let viewModel = VolunteerHomeViewModel()
        viewModel.configure(with: appState, speechService: SpeechService())
        viewModel.incomingOrder = Self.makeDispatchOrder(hasGuideDog: nil)

        viewModel.respondToDispatch(
            action: .interested,
            currentLocation: nil,
            locationAuthorized: true
        )

        let didSurface = await Self.waitUntil { viewModel.errorMessage != nil }
        XCTAssertTrue(didSurface)
        XCTAssertEqual(client.respondActions, ["INTERESTED", "ACCEPT"], "升级不止一次")
        XCTAssertEqual(viewModel.errorMessage, ErrorCode.introCallNotRequired.localizedMessage)
    }

    /// 升级走的是**同一个函数**，所以 `.accept` 独有的定位权限闸照常生效。
    /// 就地补一个 API 调用会绕过它，志愿者会在没给定位权限的情况下把单接下来。
    func testTheUpgradeStillHonoursTheAcceptOnlyLocationGate() async {
        let client = DispatchRespondStub()
        client.failNextInterestedWith = .introCallNotRequired
        let appState = AppState(apiClient: client)
        appState.currentEnvironment = .mock
        appState.volunteerProfile = Self.dispatchReadyProfile
        let viewModel = VolunteerHomeViewModel()
        viewModel.configure(with: appState, speechService: SpeechService())
        viewModel.incomingOrder = Self.makeDispatchOrder(hasGuideDog: nil)

        viewModel.respondToDispatch(
            action: .interested,
            currentLocation: nil,
            locationAuthorized: false
        )

        let didBlock = await Self.waitUntil { viewModel.errorMessage != nil }
        XCTAssertTrue(didBlock)
        XCTAssertEqual(client.respondActions, ["INTERESTED"], "定位权限闸被绕过了")
        XCTAssertEqual(viewModel.errorMessage, "需要开启定位权限才能接单")
    }

    // MARK: - 通话退出到 REMATCHING（后端 2026-08-26 N105 之后才有的那条边）

    /// 后端修 P0 之后，通话退出回的是「进通话之前那个状态」——
    /// 进通话之前是 `REMATCHING` 的话，它就回 `REMATCHING`。这条边此前不会出现。
    /// REST 轮询这一路同样不能把它当成陈旧丢掉 —— `lifecycleRank` 里
    /// `.pendingIntroCall` 是 0、`.rematching` 是 1，这是**前进**不是倒退，
    /// 但那条边此前不在 `isDirectlyFollowed` 里，只靠 `canReach` 多跳兜住。
    func testFallingBackToRematchingIsAcceptedByTheReconciler() {
        var reconciler = OrderStatusReconciler()
        reconciler.register(orderID: 611, status: .pendingIntroCall)
        let token = reconciler.requestToken(orderID: 611)

        let result = reconciler.reconcileREST(orderID: 611, candidate: .rematching, token: token)

        XCTAssertEqual(result, .applied(.rematching))
    }

    /// 落到 `REMATCHING` 时**不能**播它的常规文案「正在确认志愿者状态，请稍候」——
    /// 这一刻没有志愿者可确认，刚才那位候选人从来就没接过单。
    /// 与退回 `PENDING_MATCH` 一样，逐字复用后端的中性文案。
    func testFallingBackToRematchingSpeaksTheSameNeutralContinuationCopy() async {
        let client = IntroCallAPIClientStub()
        client.order = Self.makeOrder(orderId: 612, status: .rematching)
        let appState = AppState(apiClient: client)
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let viewModel = BlindOrderStatusViewModel()
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.order = Self.makeOrder(orderId: 612, status: .pendingIntroCall)

        viewModel.startPolling(orderId: 612)
        let didFallBack = await Self.waitUntil { viewModel.order?.status == .rematching }
        viewModel.stopPolling()

        XCTAssertTrue(didFallBack)
        XCTAssertEqual(speechService.lastSpokenText, IntroCallCopy.continuedSearch)
        XCTAssertNotEqual(
            speechService.lastSpokenText,
            RunOrderStatus.rematching.blindRunnerAnnouncement,
            "播成了「正在确认志愿者状态」——这一刻根本没有志愿者"
        )
    }

    // MARK: - 取位置 / 念距离拆成两个判据

    /// 「取不取位置」跟后端 `sharesLiveLocation()` 走，「念不念距离」只在赶来的两态。
    /// 合成一个判据时两头都错，后端 2026-08-24 点名要求拆开。
    func testFetchingLocationAndAnnouncingDistanceAreSeparateGates() {
        // 取位置：与后端 `sharesLiveLocation()` 逐态相同。
        for status in [RunOrderStatus.driverEnRoute, .driverArrived, .inProgress] {
            XCTAssertTrue(status.fetchesVolunteerLocation, "\(status) 应该取位置")
        }
        for status in [RunOrderStatus.pendingMatch, .pendingIntroCall, .pendingAccept,
                       .rematching, .noVolunteer, .completed, .cancelled, .unknown] {
            XCTAssertFalse(status.fetchesVolunteerLocation, "\(status) 不该取位置")
        }

        // 念距离：只有正在赶来的两态。
        for status in [RunOrderStatus.driverEnRoute, .driverArrived] {
            XCTAssertTrue(status.offersVolunteerDistanceToStart, "\(status) 应该念距离")
        }
        for status in [RunOrderStatus.pendingMatch, .pendingIntroCall, .pendingAccept,
                       .rematching, .noVolunteer, .inProgress, .completed, .cancelled, .unknown] {
            XCTAssertFalse(status.offersVolunteerDistanceToStart, "\(status) 不该念距离")
        }

        // ⬇️ 拦「哪天又被合回一个」：两个判据在两态上必须给出相反的答案。
        XCTAssertNotEqual(
            RunOrderStatus.inProgress.fetchesVolunteerLocation,
            RunOrderStatus.inProgress.offersVolunteerDistanceToStart,
            "IN_PROGRESS：后端给位置，但两人已经在一起了，不念距离"
        )
        // PENDING_ACCEPT 是**两条都 false** 的那一态，所以这里不能照抄上面的 `NotEqual`
        // —— 那样写在期望状态下永远红。它守的是另一件事：拆开之后别有人图省事
        // 把 `PENDING_ACCEPT` 加回任意一边（客户端曾经每 5 秒白调一次而后端恒 404）。
        XCTAssertFalse(
            RunOrderStatus.pendingAccept.fetchesVolunteerLocation,
            "PENDING_ACCEPT 不在后端 sharesLiveLocation() 里，取位置只会拿到 404"
        )
        XCTAssertFalse(
            RunOrderStatus.pendingAccept.offersVolunteerDistanceToStart,
            "PENDING_ACCEPT 还没人接单，没有距离可念"
        )
    }

    /// `PENDING_ACCEPT` 从「念距离」里去掉之后，语音查距离要给出一句**对的**理由。
    /// 「暂时收不到志愿者位置」在这一态是错的：后端本来就不下发，不是收不到。
    func testPendingAcceptExplainsThereIsNoLocationYetRatherThanSayingItCannotBeReceived() {
        let order = Self.makeOrder(orderId: 613, status: .pendingAccept)
        let speech = VoiceStatusQuery.answer(
            intent: .distance,
            order: order,
            volunteerCoordinate: nil,
            fallbackAnnouncement: order.blindRunnerAnnouncement()
        ).speech
        XCTAssertTrue(speech.contains("还没出发"), "没说清是「还没出发」而不是「收不到」：\(speech)")
        XCTAssertFalse(speech.contains("收不到"), "把「后端本来就不给」说成了「收不到」：\(speech)")
    }

    private static let dispatchReadyProfile = VolunteerProfileResponse(
        name: "测试志愿者",
        verificationStatus: "approved",
        adminReviewStatus: "approved",
        registrationStep: nil,
        canAcceptOrders: true,
        isAvailable: true,
        availableTimeSlots: nil,
        acceptsGuideDog: nil,
        paceRange: nil
    )

    private static func makeSummary(introCallOrderId: Int64?) -> VolunteerDispatchSummaryResponse {
        VolunteerDispatchSummaryResponse(
            canDispatch: true,
            notAvailableReasons: [],
            wantsDispatch: true,
            isOnline: true,
            lastLat: nil,
            lastLng: nil,
            lastLocationAt: nil,
            coverageRadiusKm: nil,
            isWithinServiceTime: true,
            availableTimeSlots: nil,
            avgRating: nil,
            totalRatings: nil,
            totalDispatched: nil,
            totalAccepted: nil,
            totalDeclined: nil,
            totalTimeout: nil,
            totalCompleted: nil,
            totalCancelled: nil,
            acceptanceRate: nil,
            activeOrders: nil,
            recentOrders: nil,
            introCallOrderId: introCallOrderId
        )
    }

    // MARK: - Fixtures

    private static let blindSideView = IntroCallView(
        counterpartName: "李*",
        counterpartPhone: "13800000002",
        counterpartPhoneMasked: nil,
        myDecision: nil,
        windowEndsAt: nil,
        startAddress: "朝阳公园南门",
        plannedStartTime: "2026-08-27T07:30:00",
        plannedEndTime: "2026-08-27T08:30:00"
    )

    private static let volunteerSideView = IntroCallView(
        counterpartName: "王*",
        counterpartPhone: nil,
        counterpartPhoneMasked: "138****1234",
        myDecision: nil,
        windowEndsAt: nil,
        startAddress: "朝阳公园南门",
        plannedStartTime: "2026-08-27T07:30:00",
        plannedEndTime: "2026-08-27T08:30:00"
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

    // MARK: - 独立通话页：本轮剩余时间

    /// 窗口还剩多久这一行，四条边界。**三条都返回 nil** —— 算不出来就不说，不猜。
    ///
    /// 口径与 `blindRunnerWaitedText` 相同：这一行是辅助信息，摆一个说不出内容的占位
    /// 比没有这一行更容易被当成真的。
    func testWindowRemainingTextOnlySpeaksWhenItHasSomethingTrueToSay() {
        let now = Date()

        // 后端形状变了 / 字段本来就是 optional。
        XCTAssertNil(IntroCallCopy.blindWindowRemainingText(windowEndsAt: nil, now: now))
        XCTAssertNil(IntroCallCopy.blindWindowRemainingText(windowEndsAt: "   ", now: now))
        XCTAssertNil(IntroCallCopy.blindWindowRemainingText(windowEndsAt: "不是时间", now: now))

        // 🚨 已经过期：窗口到点后订单转走有延迟，这中间**客户端不替后端宣布结果**。
        // 显示「已超时」而后端还在等表态，会让用户以为白打了一通电话。
        let expired = ISO8601DateFormatter.aidRunFormatter.string(from: now.addingTimeInterval(-60))
        XCTAssertNil(IntroCallCopy.blindWindowRemainingText(windowEndsAt: expired, now: now))

        // 不足 1 分钟：「还剩 0 分钟」既是噪音，又是在催一个正在打电话的人。
        let almostUp = ISO8601DateFormatter.aidRunFormatter.string(from: now.addingTimeInterval(45))
        XCTAssertNil(IntroCallCopy.blindWindowRemainingText(windowEndsAt: almostUp, now: now))

        // 正常：向下取整到分钟。
        let fresh = ISO8601DateFormatter.aidRunFormatter.string(from: now.addingTimeInterval(18 * 60 + 40))
        XCTAssertEqual(
            IntroCallCopy.blindWindowRemainingText(windowEndsAt: fresh, now: now),
            "这一轮通话还剩 18 分钟"
        )
    }

    /// 🚨 **这一行不许泄露轮次。** 无声拒绝要求盲人无从得知自己被谁拒过，
    /// 而「这是第 3 位志愿者」本身就是在告诉他前两位没成。
    func testWindowRemainingTextNeverLeaksTheRoundNumber() {
        let text = IntroCallCopy.blindWindowRemainingText(
            windowEndsAt: ISO8601DateFormatter.aidRunFormatter.string(from: Date().addingTimeInterval(600)),
            now: Date()
        )
        let leaks = ["第", "轮次", "位志愿者", "重新", "换一位", "再找"]
        for word in leaks {
            XCTAssertFalse(text?.contains(word) == true, "剩余时间文案里出现了会泄露轮次的「\(word)」：\(text ?? "nil")")
        }
    }

    // MARK: - 独立通话页：什么时候弹出来

    /// 转入通话态就自动弹 —— 盲人不会知道页面上多了一个入口，这一跳是他唯一的发现路径。
    func testIntroCallPageOpensWhenTheOrderEntersIntroCall() {
        var presentation = BlindIntroCallPresentation()
        XCTAssertFalse(presentation.isShowing)

        presentation.apply(status: .pendingIntroCall)
        XCTAssertTrue(presentation.isShowing)
    }

    /// 🚨 **关掉之后本轮不许再弹。** 没有这条就是一个关不掉的全屏页：
    /// 用户按「返回订单」→ 5 秒后轮询回来 `status` 还是 `PENDING_INTRO_CALL` → 又弹出来。
    /// 志愿者侧踩过同一个坑（`autoOpenedIntroCallOrderId`）。
    func testIntroCallPageDoesNotReopenAfterTheUserClosesItInTheSameRound() {
        var presentation = BlindIntroCallPresentation()
        presentation.apply(status: .pendingIntroCall)
        presentation.dismiss()
        XCTAssertFalse(presentation.isShowing)

        // 轮询每 5 秒把同一个状态送回来一次。三轮都不许把页面顶回用户脸上。
        for _ in 0..<3 {
            presentation.apply(status: .pendingIntroCall)
            XCTAssertFalse(presentation.isShowing, "用户已经关过这一轮的通话页，不该再自动弹出来")
        }
    }

    /// 🚩 **但「关过一次」是本轮的记号，不是这一单的。**
    ///
    /// 本轮没聊成会退回 `PENDING_MATCH`（`AGENTS.md` §5），下一位候选人上来又是
    /// `PENDING_INTRO_CALL` —— 那是一件新的、必须让用户知道的事。不复位的话，
    /// 第一次关掉之后这一单余下的每一位候选人都不再自动弹。
    func testIntroCallPageOpensAgainForTheNextCandidate() {
        var presentation = BlindIntroCallPresentation()
        presentation.apply(status: .pendingIntroCall)
        presentation.dismiss()

        // 本轮没聊成，退回派单队列。
        presentation.apply(status: .pendingMatch)
        XCTAssertFalse(presentation.isShowing)

        // 下一位候选人。
        presentation.apply(status: .pendingIntroCall)
        XCTAssertTrue(presentation.isShowing, "换了候选人是新的一轮，必须重新弹出来")
    }

    /// 本轮成了（或订单被取消）就把页面收起来，且**不留下「关过」的记号** ——
    /// 那是系统收的，不是用户关的。
    func testLeavingIntroCallClosesThePageAndClearsTheDismissMark() {
        var presentation = BlindIntroCallPresentation()
        presentation.apply(status: .pendingIntroCall)
        XCTAssertTrue(presentation.isShowing)

        // 双方都说合适 ⇒ PENDING_ACCEPT。
        presentation.apply(status: .pendingAccept)
        XCTAssertFalse(presentation.isShowing)

        // 记号已复位：这一单若因志愿者取消走 REMATCHING 再回到通话态，照样会弹。
        presentation.apply(status: .pendingIntroCall)
        XCTAssertTrue(presentation.isShowing)
    }

    /// 每一个非通话态都要收起页面。写成遍历而不是逐条断言：后端往状态机加值时，
    /// 新状态会自动被这条用例覆盖，不需要有人记得回来补一行。
    func testEveryNonIntroCallStatusClosesThePage() {
        for status in RunOrderStatus.allCases where status != .pendingIntroCall {
            var presentation = BlindIntroCallPresentation()
            presentation.apply(status: .pendingIntroCall)
            XCTAssertTrue(presentation.isShowing)

            presentation.apply(status: status)
            XCTAssertFalse(presentation.isShowing, "\(status.rawValue) 不是通话态，通话页该收起来")
        }
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

/// 记录 `POST /api/orders/{id}/respond` 的**动作序列**。
///
/// 「收到 409 之后有没有改发 ACCEPT」只有靠序列才看得出来 —— 断言 `errorMessage` 为 nil
/// 会被「什么都没做也没报错」蒙混过去。动作从请求体里解出来，不是从调用参数猜的：
/// 这样连「改发了但发的还是 INTERESTED」也拦得住。
private final class DispatchRespondStub: APIClientProtocol, @unchecked Sendable {
    enum StubError: Error { case unexpectedType, notFound }

    private(set) var respondActions: [String] = []
    /// 下一条 `INTERESTED` 用这个码失败；用掉即清。
    var failNextInterestedWith: ErrorCode?
    /// 每一条 `ACCEPT` 都用这个码失败（用来验「升级最多一次」）。
    var failEveryAcceptWith: ErrorCode?
    var order: OrderDetailResponse?

    func request<T: Decodable>(
        method: HTTPMethod,
        path: String,
        query: [String: String]?,
        body: (any Encodable & Sendable)?,
        requiresAuth: Bool
    ) async throws -> T {
        if path.hasSuffix("/respond"), method == .post {
            let action = Self.action(from: body)
            respondActions.append(action)
            if action == "INTERESTED", let code = failNextInterestedWith {
                failNextInterestedWith = nil
                throw Self.serverError(code)
            }
            if action == "ACCEPT", let code = failEveryAcceptWith {
                throw Self.serverError(code)
            }
            guard let value = EmptyResponse() as? T else { throw StubError.unexpectedType }
            return value
        }
        if method == .get, path.hasPrefix("/api/orders/") {
            guard let order, let value = order as? T else { throw StubError.notFound }
            return value
        }
        // `dispatch-summary` 等刷新调用在实现里都是 `try?`，抛出去不影响被测行为。
        throw StubError.notFound
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

    private static func serverError(_ code: ErrorCode) -> APIError {
        .serverError(ErrorResponse(code: code.rawValue, message: code.localizedMessage))
    }

    private static func action(from body: (any Encodable & Sendable)?) -> String {
        guard let body,
              let data = try? JSONEncoder().encode(body),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let action = json["action"] as? String else { return "<无 action>" }
        return action
    }
}
