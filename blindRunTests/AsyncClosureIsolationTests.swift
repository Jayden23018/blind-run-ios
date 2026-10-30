import CoreLocation
import XCTest
@testable import blindRun

/// #451：存储型 async 闭包标成 `@MainActor` 之后，「造出视图 → 调它存的闭包」这条路照样把参数与返回值原样送到。
///
/// 为什么要单独走这条路：#449 的崩溃只出现在「经闭包调用」时 —— 没标隔离的 async 函数类型在
/// approachable concurrency 下是 `nonisolated(nonsending)`，调用方传进来的 MainActor 闭包要多经一层
/// 转换 thunk，真机上参数在到达服务层前已被释放。直调 view model 的用例从不经过那层 thunk，所以全绿。
/// 这里每条都照生产代码的接线方式造视图、从 MainActor 上的 Task 调它存的闭包（与按钮按下去同一条路，
/// 参照 `VolunteerMeetupPlanTests.testSubmittingThroughTheFormClosureDeliversTheRequestIntact`）。
///
/// 守卫 `unannotated-async-closure`（`scripts/hooks/guard.mjs`）拦新写的未标注属性；这些用例守已有的接线。
@MainActor
final class AsyncClosureIsolationTests: XCTestCase {
    // MARK: - 求助屏（EmergencyCountdownView）

    /// 倒计时里按「取消」：闭包里调 `cancelCountdown`，撤的必须是服务端那条倒计时（`BlindOrderStatusView` 同一写法）。
    func testCancellingTheCountdownThroughTheScreenClosureWithdrawsTheServerCountdown() async {
        let (coordinator, safety) = EmergencySOSTests.makeCountdownFixture()
        defer { EmergencySOSTests.teardownAlarmObservers() }
        safety.triggerEmergencyResult = .success(EmergencyTriggerResponse(
            success: true,
            eventId: 950,
            status: "COUNTDOWN",
            countdownEndsAt: DateFormatter.aidRunBackendLocalDateTime.string(from: Date().addingTimeInterval(3))
        ))
        safety.cancelEmergencyResult = .success(EmergencyCancelResponse(success: true, eventId: 950, status: "CANCELLED"))
        coordinator.beginCountdown(
            order: EmergencySOSTests.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            safety: safety,
            locate: { EmergencySOSTests.coordinate(latitude: 39.915, longitude: 116.404) }
        )
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(coordinator.state.isCountingDown, "前提：已进服务端倒计时")

        var outcome: EmergencyCoordinator.TriggerOutcome?
        let screen = makeScreen(
            coordinator,
            onCancelCountdown: { outcome = await coordinator.cancelCountdown(safety: safety) }
        )
        await Task { await screen.onCancelCountdown() }.value

        XCTAssertEqual(safety.lastEventId, 950, "撤的不是这一条")
        XCTAssertEqual(safety.calls, ["triggerEmergency(_:)", "cancelEmergencyByOwner(eventId:)"])
        XCTAssertEqual(outcome?.state, .withdrawnBeforeSending)
        XCTAssertEqual(outcome?.message, "已撤回。求助没有发出，没有通知任何人。", "返回的文案经闭包后要原样回到调用方")
        XCTAssertNil(coordinator.activeEvent)
    }

    /// 求助已发出页的「撤销求助」：闭包里调 `cancelByOwner`，撤的必须是刚发出的那一条。
    func testCancellingOwnEmergencyThroughTheScreenClosureReachesTheService() async {
        let (coordinator, safety) = EmergencySOSTests.makeCountdownFixture()
        defer { EmergencySOSTests.teardownAlarmObservers() }
        safety.triggerEmergencyResult = .success(EmergencyTriggerResponse(success: true, eventId: 77, status: "CONTACT_NOTIFIED"))
        safety.cancelEmergencyResult = .success(EmergencyCancelResponse(success: true, eventId: 77, status: "FALSE_ALARM"))
        await coordinator.trigger(
            order: EmergencySOSTests.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            safety: safety,
            locate: { EmergencySOSTests.coordinate(latitude: 39.915, longitude: 116.404) }
        )
        XCTAssertEqual(coordinator.activeEvent?.eventID, 77, "前提：求助已发出")

        var outcome: EmergencyCoordinator.TriggerOutcome?
        let screen = makeScreen(
            coordinator,
            onCancelOwnEmergency: { outcome = await coordinator.cancelByOwner(safety: safety) }
        )
        await Task { await screen.onCancelOwnEmergency() }.value

        XCTAssertEqual(safety.lastEventId, 77, "撤的不是这一条")
        XCTAssertEqual(safety.calls.last, "cancelEmergencyByOwner(eventId:)")
        XCTAssertEqual(outcome?.state, .cancelledByOwner)
        XCTAssertEqual(coordinator.state, .cancelledByOwner)
        XCTAssertNil(coordinator.activeEvent)
    }

    // MARK: - 出发前留言（RunnerMessageSheet）

    /// 参数与返回值都是 `String` —— 正是 #449 那类会在 thunk 里被释放的引用计数内容。
    func testSavingThroughTheSheetClosureDeliversTheTextIntact() async throws {
        let service = FakeOrderService()
        service.runnerMessageResult = .success(RunnerMessageResponse(messageToVolunteer: "我穿红色外套"))
        let appState = AppState(orders: service)
        let viewModel = BlindOrderStatusViewModel()
        viewModel.configure(appState: appState, speechService: SpeechService())
        viewModel.order = try enRouteOrder()
        // `BlindOrderStatusView` 的接线原样：表单存着闭包，闭包里调 view model。
        let sheet = RunnerMessageSheet(initialText: "") { text in
            await viewModel.saveRunnerMessage(text)
        }

        let error = await Task { await sheet.onSave("  我穿红色外套 ") }.value

        XCTAssertNil(error)
        XCTAssertEqual(service.lastRunnerMessageText, "我穿红色外套", "留言经闭包后要原样到达服务层")
        XCTAssertEqual(service.lastOrderId, 88)
        XCTAssertEqual(viewModel.order?.messageToVolunteer, "我穿红色外套")
    }

    /// 失败时表单靠闭包的**返回值**显示错误：这句话也要原样穿过 thunk 回来。
    func testSheetClosureReturnsTheFailureMessageIntact() async throws {
        let service = FakeOrderService()
        let appState = AppState(orders: service)
        let viewModel = BlindOrderStatusViewModel()
        viewModel.configure(appState: appState, speechService: SpeechService())
        viewModel.order = try enRouteOrder()
        let tooLong = String(repeating: "红", count: RunnerMessageRequest.maxLength + 1)
        let direct = await viewModel.saveRunnerMessage(tooLong)
        let sheet = RunnerMessageSheet(initialText: "") { text in
            await viewModel.saveRunnerMessage(text)
        }

        let error = await Task { await sheet.onSave(tooLong) }.value

        XCTAssertNotNil(direct, "前提：超长留言直调时返回错误")
        XCTAssertEqual(error, direct, "错误文案经闭包回来后变了")
        XCTAssertEqual(service.callCount("updateRunnerMessage(_:orderId:)"), 0, "超长的不许发出去")
    }

    // MARK: - 陪跑员收到求助（VolunteerEmergencyAlertView）

    /// 逆地理返回 `String`、服务端兜底返回带 `String` 的结构体：两条都经视图存的闭包调用。
    func testAlertScreenClosuresReturnAddressesIntact() async {
        let safety = FakeSafetyService()
        let serverAnswer = OrderLocationAddressResponse(
            formattedAddress: "北京市朝阳区朝阳公园南门",
            latitude: 39.94,
            longitude: 116.47,
            ageSeconds: 8,
            degraded: false
        )
        safety.orderLocationAddressResult = .success(serverAnswer)
        // `VolunteerOrderFlowViews` 的接线写法：闭包里各调一次服务。
        let screen = VolunteerEmergencyAlertView(
            alert: VolunteerEmergencyAlert(eventID: 31, orderID: 4_242, message: "对方正在求助", receivedAt: Date()),
            peerName: "王",
            peerPhone: nil,
            deviceCoordinate: nil,
            isAcknowledging: false,
            onAcknowledge: {},
            reverseGeocode: { coordinate in "朝阳公园南门（\(coordinate.latitude)）" },
            serverAddress: { try? await safety.orderLocationAddress(orderId: $0) }
        )

        let place = await Task { await screen.reverseGeocode(CLLocationCoordinate2D(latitude: 39.94, longitude: 116.47)) }.value
        let address = await Task { await screen.serverAddress(4_242) }.value

        XCTAssertEqual(place, "朝阳公园南门（39.94）")
        XCTAssertEqual(address, serverAnswer, "服务端地址经闭包回来后变了")
        XCTAssertEqual(safety.orderIds, [4_242], "问的不是此订单")
    }

    // MARK: - Fixture

    private func makeScreen(
        _ coordinator: EmergencyCoordinator,
        onCancelCountdown: @escaping @MainActor () async -> Void = {},
        onCancelOwnEmergency: @escaping @MainActor () async -> Void = {}
    ) -> EmergencyCountdownView {
        EmergencyCountdownView(
            coordinator: coordinator,
            primaryContact: nil,
            onCancelCountdown: onCancelCountdown,
            onCancelOwnEmergency: onCancelOwnEmergency,
            onRetry: {},
            onClose: {}
        )
    }

    private func enRouteOrder() throws -> OrderDetailResponse {
        try JSONDecoder().decode(
            OrderDetailResponse.self,
            from: Data(#"{"orderId":88,"status":"DRIVER_EN_ROUTE"}"#.utf8)
        )
    }
}
