import XCTest
import AMapSearchKit
import AVFAudio
import CoreLocation
import SwiftUI
@testable import blindRun

@MainActor
final class BlindRunnerReviewAndRealtimeTests: XCTestCase, BlindRunTestSupport {
    func testBlindRunnerActiveOrderPollingIntervalStaysFiveSeconds() {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let viewModel = BlindOrderStatusViewModel()
        viewModel.configure(appState: appState, speechService: SpeechService())
        viewModel.order = makeOrder(orderId: 1, status: .inProgress)

        XCTAssertEqual(viewModel.effectivePollingInterval, AppConstants.Timing.orderPollingInterval)
    }

    func testBlindRunnerCompletedOrderSubmitsReviewRequest() async throws {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let viewModel = BlindOrderStatusViewModel()
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.order = makeOrder(orderId: 2, status: .completed)
        viewModel.reviewRating = 5
        viewModel.reviewComment = "体验很好"

        await viewModel.submitReview()

        XCTAssertTrue(viewModel.didSubmitReview)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(speechService.lastSpokenText, "评价已提交，感谢反馈。")
    }

    /// 后端 2026-07-31 起把「已评价过此订单」从 `DUPLICATE_ORDER` 拆成专用码
    /// `REVIEW_ALREADY_SUBMITTED`。此前两个语义共用一个码，重复评价会被念成
    /// 「您已有进行中的订单」这句完全不相干的话（对只靠语音的用户是纯误导）。
    /// 这条用例是防退回门：重复评价必须念「已评价」，且**绝不能**出现「进行中的订单」。
    func testDuplicateReviewIsTreatedAsAlreadyReviewedNotInProgressOrderCopy() async {
        let client = FailingAPIClient(error: APIError.serverError(
            ErrorResponse(code: "REVIEW_ALREADY_SUBMITTED", message: "已评价过此订单")
        ))
        let appState = AppState(apiClient: client)
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let viewModel = BlindOrderStatusViewModel()
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.order = makeOrder(orderId: 3, status: .completed)
        viewModel.reviewRating = 5

        await viewModel.submitReview()

        // 已评价不是失败：页面切到已评价态，不显示错误。
        XCTAssertTrue(viewModel.didSubmitReview)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(speechService.lastSpokenText, "您已评价过此订单。")
        XCTAssertFalse(
            (speechService.lastSpokenText ?? "").contains("进行中的订单"),
            "重复评价被念成了下单受阻的文案"
        )
    }

    /// 拆码后两个码各说各话：`DUPLICATE_ORDER` 只剩下单场景；且不得再有
    /// 「以后端 message 为准」的止血补丁——本地文案就是权威。
    ///
    /// 🚩 2026-09-05 改口径（跨天预约上线，见 `AGENTS.md` §5）：后端判据从「有任何未走完的单」
    /// 改成**时段冲突**，所以这里断言的是「说了是时间段的事」，并**反过来钉住不许再出现
    /// 「进行中的订单」** —— 那句话现在会让用户去取消一张完全不冲突的预约。
    func testDuplicateOrderAndReviewAlreadySubmittedCarryDistinctCopy() {
        XCTAssertTrue(
            ErrorCode.duplicateOrder.localizedMessage.contains("时间段"),
            "DUPLICATE_ORDER 拦的是时段冲突，文案要说清是哪一维度撞了"
        )
        XCTAssertFalse(
            ErrorCode.duplicateOrder.localizedMessage.contains("进行中的订单"),
            "旧文案自 2026-09-05 起是错的：约了后天的单之后今天临时想跑照样能下单"
        )
        XCTAssertTrue(ErrorCode.reviewAlreadySubmitted.localizedMessage.contains("评价"))
        XCTAssertNotEqual(
            ErrorCode.duplicateOrder.localizedMessage,
            ErrorCode.reviewAlreadySubmitted.localizedMessage
        )

        // 止血补丁撤除后，本地文案不再被后端 message 顶掉。
        let error = APIError.serverError(
            ErrorResponse(code: "DUPLICATE_ORDER", message: "您有进行中的订单，请完成后再下单")
        )
        XCTAssertEqual(error.localizedMessage, ErrorCode.duplicateOrder.localizedMessage)
    }

    /// 2026-08-13 起「重复当前状态」在服务进行中还要念**约定的结束时间**，
    /// 所以这里不再与状态级的定值比较（那个定值不含时间）。
    ///
    /// 加它的理由不是信息更全：后端 N63 修好后，超过 `plannedEnd` 15 分钟会推 `ORDER_OVERDUE`。
    /// 用户从没听到过这个约定，那条告警对他就只是一句没有参照系的话。而这一页把结束时间
    /// 折叠在「预约信息」的 `DisclosureGroup` 里，跑步途中不会有人去展开它。
    func testBlindRunnerRepeatStatusSpeaksInServiceStateWithTheAgreedEndTime() {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let viewModel = BlindOrderStatusViewModel()
        viewModel.configure(appState: appState, speechService: speechService)
        let order = makeOrder(orderId: 1, status: .inProgress)
        viewModel.order = order

        viewModel.repeatStatus()

        let spoken = speechService.lastSpokenText ?? ""
        XCTAssertTrue(spoken.hasPrefix(RunOrderStatus.inProgress.blindRunnerAnnouncement), "状态本身仍要先说")
        XCTAssertTrue(
            spoken.contains("2026-06-25T21:00:00Z".displayDateTime),
            "服务进行中必须念到约定的结束时间，否则 ORDER_OVERDUE 到达时用户没有参照系"
        )
    }

    func testBlindRunnerHomeAppliesRealtimeStatusWhileBackgroundRefreshIsSuspended() async {
        let client = CancellationSuspendingAPIClient()
        let appState = AppState(apiClient: client)
        let speechService = SpeechService()
        let initialOrder = makeOrder(orderId: 703, status: .pendingAccept)
        let viewModel = BlindRunnerHomeViewModel(loadTimeout: 0.2)
        viewModel.configure(with: appState, speechService: speechService)
        viewModel.activeOrder = initialOrder
        appState.liveEscortCoordinator.updateOwnedOrder(
            orderID: initialOrder.orderId,
            status: initialOrder.status
        )
        let refresh = Task { await viewModel.loadActiveOrder() }
        _ = await waitUntil { client.requestCount(for: "/api/orders/active") == 1 }

        appState.realtimeCoordinator.simulateIncomingEventForTesting(
            .orderStatusChanged(WSOrderStatusChanged(
                type: WSMessageType.orderStatusChanged.rawValue,
                orderId: initialOrder.orderId,
                fromStatus: RunOrderStatus.pendingAccept.rawValue,
                toStatus: RunOrderStatus.driverEnRoute.rawValue,
                message: nil,
                ttsText: nil,
                priority: "HIGH",
                timestamp: "2026-07-23T12:00:00Z"
            ))
        )
        let didApply = await waitUntil {
            viewModel.activeOrder?.status == .driverEnRoute
        }

        XCTAssertTrue(didApply)
        XCTAssertEqual(
            speechService.lastSpokenText,
            viewModel.activeOrder?.blindRunnerAnnouncement()
        )
        XCTAssertEqual(viewModel.currentStatusText.contains("陪跑员出发中"), true)

        refresh.cancel()
        await refresh.value
        XCTAssertEqual(viewModel.activeOrder?.status, .driverEnRoute)
    }

    func testBlindOrderStatusAppliesRealtimeEnRouteWhileDetailQueryIsSuspended() async {
        let initialOrder = makeOrder(orderId: 704, status: .pendingAccept)
        let client = TransitionConfirmationFixture(
            confirmation: .suspended,
            order: initialOrder
        )
        let appState = AppState(orders: client.service)
        let speechService = SpeechService()
        let viewModel = BlindOrderStatusViewModel()
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.order = initialOrder
        viewModel.startPolling(orderId: initialOrder.orderId)
        let didStartPolling = await waitUntil { client.getRequestCount == 1 }
        XCTAssertTrue(didStartPolling)

        appState.realtimeCoordinator.simulateIncomingEventForTesting(
            .orderStatusChanged(WSOrderStatusChanged(
                type: WSMessageType.orderStatusChanged.rawValue,
                orderId: initialOrder.orderId,
                fromStatus: RunOrderStatus.pendingAccept.rawValue,
                toStatus: RunOrderStatus.driverEnRoute.rawValue,
                message: nil,
                ttsText: nil,
                priority: "HIGH",
                timestamp: "2026-07-23T12:00:00Z"
            ))
        )
        let didApply = await waitUntil {
            viewModel.order?.status == .driverEnRoute && !viewModel.isLoading
        }

        XCTAssertTrue(didApply)
        XCTAssertEqual(
            speechService.lastSpokenText,
            SpeechService.statusAnnouncement(for: .driverEnRoute)
        )

        client.releaseSuspendedRequests()
        let didDiscardLateRegression = await waitUntil {
            viewModel.order?.status == .driverEnRoute
        }
        XCTAssertTrue(didDiscardLateRegression)
        viewModel.stopPolling()
    }
}
