import XCTest
@testable import blindRun

/// 派单摘要的 `upcomingOrders`（后端 #774，iOS #471）：已接单、还没出发的单（`PENDING_ACCEPT` / `SCHEDULED_CONFIRMED`）。
///
/// 契约两条红线各有一条用例守：
/// - `nil` 与 `[]` 意思相反：`[]` = 确实没有（不再打 `orders/mine`）；`nil` = 服务端没取到（回落到两条 `orders/mine`）
/// - 不并进 `activeOrders`、不注册进位置协同（这两态不共享实时位置，注册了安全网空转）
@MainActor
final class VolunteerUpcomingOrdersTests: XCTestCase {

    func testNullAndEmptyDecodeDifferently() throws {
        func decode(_ tail: String) throws -> VolunteerDispatchSummaryResponse {
            try JSONDecoder().decode(VolunteerDispatchSummaryResponse.self, from: Data(#"{"wantsDispatch":true\#(tail)}"#.utf8))
        }
        XCTAssertEqual(try decode(#","upcomingOrders":[]"#).upcomingOrders?.count, 0, "空数组 = 确实没有")
        XCTAssertNil(try decode(#","upcomingOrders":null"#).upcomingOrders, "null = 服务端没取到")
        XCTAssertNil(try decode("").upcomingOrders, "老服务端没有这个键，同 null")
    }

    /// 摘要带了：直接当预约列表，不打 `orders/mine`；不进 `activeOrder`、不注册进位置协同。
    func testUpcomingFromSummaryFillsTheListWithoutTouchingActiveOrdersOrLocationSharing() async {
        let orders = FakeOrderService()
        orders.dispatchSummaryResult = .success(Self.summary(upcoming: #"[{"orderId":72,"status":"SCHEDULED_CONFIRMED","plannedStartTime":"2026-11-02T07:00:00"},{"orderId":71,"status":"PENDING_ACCEPT","plannedStartTime":"2026-11-01T07:00:00"}]"#))
        let (appState, viewModel) = Self.makeHome(orders: orders)

        await viewModel.load(currentLocation: nil, locationAuthorized: false)
        await Self.waitUntil { viewModel.scheduledOrders.count == 2 }

        XCTAssertEqual(viewModel.scheduledOrders.map(\.orderId), [71, 72], "按开跑时间升序")
        XCTAssertNil(viewModel.activeOrder, "预约单并进了活跃订单")
        XCTAssertTrue(appState.realtimeCoordinator.registeredActiveOrderIDsForTesting.isEmpty, "预约单注册进了位置协同")
        try? await Task.sleep(nanoseconds: 500_000_000)  // 让辅助加载那条 Task 跑完再断言它没打 orders/mine
        XCTAssertEqual(orders.lastVolunteerOrdersStatuses, [], "摘要带了 upcomingOrders 还在打 orders/mine")
    }

    /// `[]` = 确实没有：列表空、也不回落去打 `orders/mine`。
    func testEmptyUpcomingMeansNoneAndDoesNotFallBack() async {
        let orders = FakeOrderService()
        orders.dispatchSummaryResult = .success(Self.summary(upcoming: "[]"))
        orders.scheduledOrdersResult = .success(Self.page([OrderDetailResponse.preview(orderId: 80, status: .scheduledConfirmed)]))
        let (appState, viewModel) = Self.makeHome(orders: orders)

        await viewModel.load(currentLocation: nil, locationAuthorized: false)
        try? await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertNotNil(viewModel.dispatchSummary, "前提：摘要真的灌进来了（AppState 被丢掉时 load 直接返回，这条会假绿）")
        XCTAssertTrue(viewModel.scheduledOrders.isEmpty)
        XCTAssertEqual(orders.lastVolunteerOrdersStatuses, [], "空数组被当成了「没取到」")
        withExtendedLifetime(appState) {}
    }

    /// `null` = 服务端没取到：回落到两条 `orders/mine`，按回来的渲染。
    func testNullUpcomingFallsBackToTheOrderLists() async {
        let orders = FakeOrderService()
        orders.dispatchSummaryResult = .success(Self.summary(upcoming: "null"))
        orders.scheduledOrdersResult = .success(Self.page([OrderDetailResponse.preview(orderId: 81, status: .scheduledConfirmed)]))
        orders.pendingAcceptOrdersResult = .success(Self.page([]))
        let (appState, viewModel) = Self.makeHome(orders: orders)

        await viewModel.load(currentLocation: nil, locationAuthorized: false)
        await Self.waitUntil { !viewModel.scheduledOrders.isEmpty }

        XCTAssertEqual(viewModel.scheduledOrders.map(\.orderId), [81])
        XCTAssertEqual(
            orders.lastVolunteerOrdersStatuses.sorted { $0.rawValue < $1.rawValue }, [.pendingAccept, .scheduledConfirmed],
            "null 被当成了空列表，没有回落"
        )
        withExtendedLifetime(appState) {}
    }

    /// 确认 / 释放成功后本地移走了那一单：发出早于这一刻的摘要（在途的那次刷新）不许把它放回来（复核 B）。
    func testASummaryRequestedBeforeALocalChangeDoesNotBringTheOrderBack() async {
        let orders = FakeOrderService()
        let summary = Self.summary(upcoming: #"[{"orderId":73,"status":"SCHEDULED_CONFIRMED","plannedStartTime":"2026-11-03T07:00:00"}]"#)
        orders.dispatchSummaryResult = .success(summary)
        orders.confirmDepartureResult = .success(())
        let (appState, viewModel) = Self.makeHome(orders: orders)
        await viewModel.load(currentLocation: nil, locationAuthorized: false)
        await Self.waitUntil { viewModel.scheduledOrders.count == 1 }
        XCTAssertEqual(viewModel.scheduledOrders.map(\.orderId), [73], "前提：摘要里那一单进了列表")
        let beforeTheChange = Date()

        await viewModel.confirmScheduledDeparture(orderID: 73)
        XCTAssertEqual(viewModel.acceptedDispatchOrderId, 73, "前提：确认真的成功了（失败时列表本来就不动）")
        XCTAssertTrue(viewModel.scheduledOrders.isEmpty)

        viewModel.apply(summary: summary, requestedAt: beforeTheChange)
        XCTAssertTrue(viewModel.scheduledOrders.isEmpty, "在途的旧摘要把刚确认的单放回来了")
        viewModel.apply(summary: summary, requestedAt: Date().addingTimeInterval(1))
        XCTAssertEqual(viewModel.scheduledOrders.map(\.orderId), [73], "改动之后发出的摘要照常生效")
        withExtendedLifetime(appState) {}
    }

    // MARK: - Fixture

    private static func summary(upcoming: String) -> VolunteerDispatchSummaryResponse {
        let json = #"{"canDispatch":true,"notAvailableReasons":[],"wantsDispatch":true,"activeOrders":[],"upcomingOrders":\#(upcoming)}"#
        // swiftlint:disable:next force_try 桩数据解不出说明这条用例本身写坏了，该当场炸。
        return try! JSONDecoder().decode(VolunteerDispatchSummaryResponse.self, from: Data(json.utf8))
    }

    /// ⚠️ 返回的 `AppState` 要攥到用例结束：view model 对它是 `weak`，丢掉（`let (_, vm)`）它就释放，
    /// `load()` 开头直接返回 —— 10-29 真机上三条用例因此红 / 假绿（同类见 #598）。
    private static func makeHome(orders: FakeOrderService) -> (AppState, VolunteerHomeViewModel) {
        let appState = AppState(orders: orders)
        appState.currentEnvironment = .mock
        let viewModel = VolunteerHomeViewModel()
        viewModel.configure(with: appState, speechService: SpeechService())
        return (appState, viewModel)
    }

    private static func page(_ orders: [OrderDetailResponse]) -> PagedOrderResponse {
        PagedOrderResponse(
            content: orders, totalElements: Int64(orders.count), totalPages: orders.isEmpty ? 0 : 1,
            number: 0, size: 20, first: true, last: true, empty: orders.isEmpty
        )
    }

    private static func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}
