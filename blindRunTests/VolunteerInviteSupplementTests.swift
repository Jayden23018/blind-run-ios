import XCTest
import AMapSearchKit
import AVFAudio
import CoreLocation
import SwiftUI
@testable import blindRun

@MainActor
final class VolunteerInviteSupplementTests: XCTestCase, BlindRunTestSupport {
    // MARK: - 邀请卡的补数（GET /api/orders/available）

    /// 设计交付 v3 §4.4.2 第 7 项那行「全盲，用引导绳」的数据来源。
    ///
    /// 🔴 **必须按 `orderId` 匹配，不许「取第一条」。** 那个端点返回的是「附近可接的单」，
    /// 按距离升序、最多 20 条，正在等我回复的那一单可能排在任何位置。
    /// 取第一条的表现是把**别人那一单**的视力情况印在这张卡上 —— 而屏幕上完全看不出来，
    /// 陪跑员照着它准备牵引绳，见面第一下就错。
    ///
    /// 验红：把 `merge` 里的 `byID[invite.id]` 换成 `orders.first`，这条立刻红在
    /// 「不许把别人那一单的引导方式安到这一单头上」。
    func testInviteSupplementIsMatchedByOrderIdNotByPosition() {
        let invites = [
            VolunteerInviteState(
                order: makeDispatchOrder(orderId: 7),
                receivedAt: Date(),
                expiresAt: Date().addingTimeInterval(30),
                remainingSeconds: 30,
                outcome: nil
            )
        ]
        // 列表第一条是**别人的单**，我们那一单排在后面 —— 这正是按距离升序的真实形状。
        let orders = [
            AvailableOrderResponse(
                orderId: 99,
                visionLevel: VisionLevel.lowVision.rawValue,
                tetherPreference: TetherPreference.verbalOnly.rawValue,
                expectedDurationMinutes: 30
            ),
            AvailableOrderResponse(
                orderId: 7,
                visionLevel: VisionLevel.totalBlind.rawValue,
                tetherPreference: TetherPreference.tetherRope.rawValue,
                expectedDurationMinutes: 60
            )
        ]

        let merged = VolunteerInviteState.merge(orders, into: invites)

        XCTAssertEqual(
            merged.first?.supplement?.runnerSummary,
            "全盲，牵引绳",
            "不许把别人那一单的引导方式安到此订单头上"
        )
        XCTAssertEqual(merged.first?.supplement?.durationText, "60 分钟")
    }

    /// 匹配不到就**保持 nil** —— 跑者那一行整行不渲染，不占位、不编。
    ///
    /// 两种合法的空/不含：志愿者还没上报过位置、资质未通过审核，后端都返空数组
    /// （契约 `api_spec.yaml:3300-3304`）。
    func testInviteSupplementStaysEmptyWhenThisOrderIsNotInTheList() {
        let invites = [
            VolunteerInviteState(
                order: makeDispatchOrder(orderId: 7),
                receivedAt: Date(),
                expiresAt: Date().addingTimeInterval(30),
                remainingSeconds: 30,
                outcome: nil
            )
        ]

        XCTAssertNil(VolunteerInviteState.merge([], into: invites).first?.supplement)
        XCTAssertNil(
            VolunteerInviteState.merge(
                [AvailableOrderResponse(
                    orderId: 8,
                    visionLevel: VisionLevel.totalBlind.rawValue,
                    tetherPreference: nil,
                    expectedDurationMinutes: nil
                )],
                into: invites
            ).first?.supplement
        )
    }

    /// 档案里两项都没填时 `runnerSummary` 为 nil ⇒ 跑者行整行不渲染。
    ///
    /// 契约对这两个字段都写着「`null` = 盲人档案缺失，**客户端不要脑补默认值**」
    /// （`api_spec.yaml:7284`、`:7298`）—— 把「不知道」显示成「全盲」同样是错的。
    func testInviteRunnerRowDisappearsWhenTheProfileHasNeitherField() {
        let empty = VolunteerInviteSupplement(
            visionLevel: nil, tetherPreference: nil, expectedDurationMinutes: 45
        )
        XCTAssertNil(empty.runnerSummary)
        XCTAssertTrue(empty.escortNeeds.isEmpty)
        // 「跑多久」是独立的一项，不跟着那两项一起消失。
        XCTAssertEqual(empty.durationText, "45 分钟")
    }

    /// 认得出字段、认不出取值时**留着这一行并叫人当面问**，不静默丢掉。
    ///
    /// 丢掉等于告诉陪跑员「跑者没有偏好」，而真实情况是「跑者填了，只是这个版本不认识」——
    /// 与 `OrderDetailResponse.escortNeeds` 同一条口径（后端往枚举加值时不许整条崩）。
    func testInviteSupplementKeepsUnknownEnumValuesAsAnAskInPersonLine() {
        let supplement = VolunteerInviteSupplement(
            visionLevel: "SOMETHING_NEW",
            tetherPreference: "ANOTHER_NEW_ONE",
            expectedDurationMinutes: nil
        )
        XCTAssertEqual(
            supplement.runnerSummary,
            "\(EscortNeed.confirmInPerson)，\(EscortNeed.confirmInPerson)"
        )
        XCTAssertNil(supplement.durationText)
    }

    /// 收到派单之后**真的会去打那条端点**，并把结果灌进当前这张卡。
    ///
    /// 🚩 上面四条全是纯函数，它们全绿也可能一行都没接线 —— 这一条断的是接线本身
    /// （`enqueue` → `loadInviteSupplements` → `merge`）。
    func testReceivingADispatchFetchesTheSupplementAndFillsTheCard() async throws {
        let orders = FakeOrderService()
        orders.availableOrdersResult = .success([
            AvailableOrderResponse(
                orderId: 42,
                visionLevel: VisionLevel.totalBlind.rawValue,
                tetherPreference: TetherPreference.armHold.rawValue,
                expectedDurationMinutes: 90
            )
        ])
        let appState = AppState(orders: orders)
        appState.currentEnvironment = .mock
        let viewModel = VolunteerHomeViewModel()
        viewModel.configure(with: appState, speechService: SpeechService())

        let webSocketService = WebSocketService()
        appState.webSocketService = webSocketService
        webSocketService.simulateIncomingEventForTesting(.newOrder(makeDispatchOrder(orderId: 42)))

        let didFill = await waitUntil { viewModel.currentInvite?.supplement != nil }
        XCTAssertTrue(didFill, "收到派单之后应当去 /api/orders/available 把跑者那一行补上")
        XCTAssertEqual(viewModel.currentInvite?.supplement?.runnerSummary, "全盲，搀扶")
        XCTAssertEqual(orders.callCount("availableOrders()"), 1)
    }

    /// 标题行**恒报数**，只有 1 条时也写「1 个新邀请」（项目负责人 2026-09-18 拍板）。
    ///
    /// 验红：改回 `count > 1 ? "\(count) 个新邀请" : "新的陪跑邀请"`，这条立刻红。
    ///
    /// 为什么值得一条用例：标题右边现在**恒挂分页点**，一条时是一枚孤零零的长条 ——
    /// 配「新的陪跑邀请」会让人以为还有别的没显示出来。两者说的必须是同一件事。
    func testInviteSheetTitleAlwaysReportsTheCount() {
        XCTAssertEqual(VolunteerInviteCopy.sheetTitle(count: 1), "1 个新邀请")
        XCTAssertEqual(VolunteerInviteCopy.sheetTitle(count: 3), "3 个新邀请")
        // 队列空的那一帧（收起动画还没走完）不许出现「0 个新邀请」。
        XCTAssertEqual(VolunteerInviteCopy.sheetTitle(count: 0), "1 个新邀请")
    }

    func testVolunteerHomeResubscribesWhenWebSocketServiceIsReplaced() async throws {
        let appState = AppState()
        appState.currentEnvironment = .mock
        appState.updateVolunteerProfile(makeApprovedVolunteerProfile())
        let viewModel = VolunteerHomeViewModel()

        viewModel.configure(with: appState, speechService: SpeechService())

        let firstWebSocketService = WebSocketService()
        appState.webSocketService = firstWebSocketService
        firstWebSocketService.simulateIncomingEventForTesting(.newOrder(makeDispatchOrder(orderId: 41)))

        let didReceiveInitialEvent = await waitUntil { viewModel.incomingOrder?.orderId == 41 }
        XCTAssertTrue(didReceiveInitialEvent)
        viewModel.dismissDispatch()

        let replacementWebSocketService = WebSocketService()
        appState.webSocketService = replacementWebSocketService
        firstWebSocketService.simulateIncomingEventForTesting(.newOrder(makeDispatchOrder(orderId: 40)))

        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(viewModel.incomingOrder)

        replacementWebSocketService.simulateIncomingEventForTesting(.newOrder(makeDispatchOrder(orderId: 43)))

        let didReceiveReplacementEvent = await waitUntil { viewModel.incomingOrder?.orderId == 43 }
        XCTAssertTrue(didReceiveReplacementEvent)
    }

    func testVolunteerHomeActiveOrderFiltersVolunteerServiceStatuses() throws {
        let activeOrder = try XCTUnwrap(VolunteerHomeViewModel.activeVolunteerOrder(from: [
            makeOrder(orderId: 1, status: .pendingMatch, createdAt: "2026-06-25T10:00:00Z"),
            makeOrder(orderId: 2, status: .pendingAccept, createdAt: "2026-06-25T11:00:00Z"),
            makeOrder(orderId: 3, status: .driverEnRoute, createdAt: "2026-06-25T12:00:00Z"),
            makeOrder(orderId: 4, status: .completed, createdAt: "2026-06-25T13:00:00Z"),
            makeOrder(orderId: 5, status: .cancelled, createdAt: "2026-06-25T14:00:00Z")
        ]))

        XCTAssertEqual(activeOrder.orderId, 3)
    }

    func testVolunteerHomeActiveOrderIgnoresTerminalOrders() {
        let activeOrder = VolunteerHomeViewModel.activeVolunteerOrder(from: [
            makeOrder(orderId: 1, status: .pendingMatch),
            makeOrder(orderId: 2, status: .completed),
            makeOrder(orderId: 3, status: .cancelled),
            makeOrder(orderId: 4, status: .noVolunteer)
        ])

        XCTAssertNil(activeOrder)
    }

    func testVolunteerHomeLoadShowsAcceptedOrderAsActiveOrder() async throws {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let viewModel = VolunteerHomeViewModel()
        viewModel.configure(with: appState, speechService: SpeechService())

        await viewModel.load(currentLocation: nil, locationAuthorized: false)
        XCTAssertNil(viewModel.activeOrder)

        appState.updateVolunteerProfile(makeApprovedVolunteerProfile())
        viewModel.incomingOrder = makeDispatchOrder(orderId: 1)
        viewModel.respondToDispatch(
            action: .accept,
            currentLocation: CLLocationCoordinate2D(latitude: 39.905, longitude: 116.408),
            locationAuthorized: true
        )

        // 等的是「接下来了」而不是「导航出去了」—— 接单之后卡片原地变「已约好」，
        // 要等用户点「查看订单」才导航（设计交付 v3 §4.4.3）。这一步只是同步点，
        // 这条用例真正要验的是下面那次 `load` 之后 `activeOrder` 是不是那一单。
        let didAccept = await waitUntil { viewModel.currentInvite?.outcome == .accepted }
        XCTAssertTrue(didAccept)

        await viewModel.load(currentLocation: nil, locationAuthorized: false)

        XCTAssertEqual(viewModel.activeOrder?.orderId, 1)
        XCTAssertEqual(viewModel.activeOrder?.status, .pendingAccept)
    }

    func testCurrentValueReplayGateRejectsPublisherReplayAcrossViewRecalculation() {
        var healthGate = CurrentValueReplayGate<LiveEscortHealthState>()

        XCTAssertTrue(healthGate.accepts(.active(background: false)))
        XCTAssertFalse(healthGate.accepts(.active(background: false)))
        XCTAssertTrue(healthGate.accepts(.active(background: true)))
        XCTAssertFalse(healthGate.accepts(.active(background: true)))
        XCTAssertTrue(healthGate.accepts(.idle))
        XCTAssertTrue(healthGate.accepts(.active(background: false)))

        let notificationID = UUID()
        var notificationGate = CurrentValueReplayGate<UUID>()
        XCTAssertTrue(notificationGate.accepts(notificationID))
        XCTAssertFalse(notificationGate.accepts(notificationID))
        XCTAssertTrue(notificationGate.accepts(UUID()))
    }
}
